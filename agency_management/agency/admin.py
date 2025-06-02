# agency/admin.py - Advanced allocation system with weekly/monthly grid
from django.contrib import admin
from django.db.models import Sum, Q
from django.utils.html import format_html
from django.utils.safestring import mark_safe
from django.template.response import TemplateResponse
from django.urls import path
from django.shortcuts import redirect
from django.contrib import messages
from django.http import JsonResponse
from dateutil.relativedelta import relativedelta
from decimal import Decimal
import json
import calendar
from datetime import date, datetime, timedelta

# Import models
from .models import (
    Company, UserProfile, Client, Project, 
    ProjectAllocation, Expense, ContractorExpense
)

# Try to import optional models
try:
    from .models import Cost, CapacitySnapshot
    COST_MODEL_EXISTS = True
except ImportError:
    COST_MODEL_EXISTS = False

try:
    from .models import MonthlyRevenue
    MONTHLY_REVENUE_EXISTS = True
except ImportError:
    MONTHLY_REVENUE_EXISTS = False


# Basic Admin Classes
@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'created_at']
    search_fields = ['name', 'code']


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate_display', 'is_project_manager']
    list_filter = ['role', 'status', 'company', 'is_project_manager']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']
    
    def hourly_rate_display(self, obj):
        if self.request.user.is_superuser:
            return f"${obj.hourly_rate:.2f}"
        return "---"
    hourly_rate_display.short_description = "Hourly Rate"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager']
    list_filter = ['status', 'company']
    search_fields = ['name']


# Enhanced Project Admin with Advanced Allocations
@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'start_date', 'end_date', 
                    'total_revenue_display', 'team_size', 'allocation_status']
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    autocomplete_fields = ['client', 'project_manager']
    
    # Remove team_members from fieldsets - it will be managed in the allocation grid
    fieldsets = (
        ('Project Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status', 'revenue_type')
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date'),
            'description': 'Set project dates to determine the allocation periods.'
        }),
        ('Financials', {
            'fields': ('total_revenue', 'total_hours'),
        }),
        ('Management', {
            'fields': ('project_manager',),
        })
    )
    
    class Media:
        css = {
            'all': ('admin/css/project_admin_advanced.css',)
        }
        js = ('admin/js/project_allocation_advanced.js',)
    
    def get_form(self, request, obj=None, **kwargs):
        request._obj_ = obj
        return super().get_form(request, obj, **kwargs)
    
    def total_revenue_display(self, obj):
        return f"${int(obj.total_revenue):,}"
    total_revenue_display.short_description = "Revenue"
    
    def team_size(self, obj):
        # Count unique team members from allocations
        team_count = obj.allocations.values('user_profile').distinct().count()
        return f"{team_count} member{'s' if team_count != 1 else ''}"
    team_size.short_description = "Team"
    
    def allocation_status(self, obj):
        if not obj.total_hours:
            return mark_safe('<span style="color:#999;">—</span>')
            
        allocated = obj.allocations.aggregate(total=Sum('allocated_hours'))['total'] or Decimal('0')
        total = obj.total_hours
        
        if total > 0:
            percentage = (float(allocated) / float(total)) * 100
            color = '#22c55e' if percentage >= 80 else '#f97316' if percentage >= 50 else '#ef4444'
            
            width = min(int(percentage), 100)
            html = (
                f'<div style="width:100px; background:#e5e7eb; border-radius:3px; overflow:hidden;">'
                f'<div style="width:{width}px; background:{color}; color:white; text-align:center; '
                f'padding:2px 0; font-size:12px;">{int(percentage)}%</div>'
                f'</div>'
            )
            return mark_safe(html)
        return mark_safe('<span style="color:#999;">No hours</span>')
    allocation_status.short_description = "Allocated"
    
    def change_view(self, request, object_id, form_url='', extra_context=None):
        extra_context = extra_context or {}
        obj = self.get_object(request, object_id)
        
        if obj and obj.start_date and obj.end_date:
            # Calculate project periods for the grid
            periods = []
            current_date = obj.start_date
            
            # Determine if we should show weeks or months based on project duration
            project_days = (obj.end_date - obj.start_date).days
            use_weeks = project_days <= 90  # Use weeks for projects 3 months or less
            
            if use_weeks:
                # Weekly view
                while current_date <= obj.end_date:
                    week_end = current_date + timedelta(days=6)
                    if week_end > obj.end_date:
                        week_end = obj.end_date
                    
                    periods.append({
                        'type': 'week',
                        'start_date': current_date,
                        'end_date': week_end,
                        'label': f"Week {current_date.strftime('%m/%d')}",
                        'year': current_date.year,
                        'month': current_date.month,
                        'week': current_date.isocalendar()[1]
                    })
                    current_date = week_end + timedelta(days=1)
            else:
                # Monthly view
                while current_date <= obj.end_date:
                    # Get last day of current month
                    if current_date.month == 12:
                        month_end = date(current_date.year + 1, 1, 1) - timedelta(days=1)
                    else:
                        month_end = date(current_date.year, current_date.month + 1, 1) - timedelta(days=1)
                    
                    if month_end > obj.end_date:
                        month_end = obj.end_date
                    
                    periods.append({
                        'type': 'month',
                        'start_date': current_date,
                        'end_date': month_end,
                        'label': current_date.strftime('%b %Y'),
                        'year': current_date.year,
                        'month': current_date.month
                    })
                    
                    # Move to first day of next month
                    if current_date.month == 12:
                        current_date = date(current_date.year + 1, 1, 1)
                    else:
                        current_date = date(current_date.year, current_date.month + 1, 1)
            
            extra_context.update({
                'project': obj,
                'periods': json.dumps([{
                    'type': p['type'],
                    'start_date': p['start_date'].isoformat(),
                    'end_date': p['end_date'].isoformat(),
                    'label': p['label'],
                    'year': p['year'],
                    'month': p['month'],
                    'week': p.get('week', 0)
                } for p in periods]),
                'use_weeks': use_weeks,
                'show_allocation_grid': True
            })
        else:
            extra_context['show_allocation_grid'] = False
        
        return super().change_view(request, object_id, form_url, extra_context)
    
    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path('<path:object_id>/get-allocation-data/',
                 self.admin_site.admin_view(self.get_allocation_data_view),
                 name='agency_project_get_allocation_data'),
            path('<path:object_id>/save-allocations/', 
                 self.admin_site.admin_view(self.save_allocations_view), 
                 name='agency_project_save_allocations'),
            path('<path:object_id>/available-members/',
                 self.admin_site.admin_view(self.get_available_members_view),
                 name='agency_project_available_members'),
            path('<path:object_id>/add-member/',
                 self.admin_site.admin_view(self.add_member_view),
                 name='agency_project_add_member'),
            path('<path:object_id>/remove-member/',
                 self.admin_site.admin_view(self.remove_member_view),
                 name='agency_project_remove_member'),
            path('<path:object_id>/auto-allocate/',
                 self.admin_site.admin_view(self.auto_allocate_view),
                 name='agency_project_auto_allocate'),
        ]
        return custom_urls + urls
    
    def get_allocation_data_view(self, request, object_id):
        """Get team members and existing allocations"""
        try:
            project = self.get_object(request, object_id)
            if not project:
                return JsonResponse({'error': 'Project not found'}, status=404)
            
            # Get all team members who have allocations on this project
            allocated_member_ids = project.allocations.values_list('user_profile_id', flat=True).distinct()
            
            # Get those team members plus any assigned through team_members field
            team_members = UserProfile.objects.filter(
                Q(id__in=allocated_member_ids) | 
                Q(assigned_projects=project)
            ).distinct().select_related('user')
            
            team_member_data = []
            for member in team_members:
                team_member_data.append({
                    'id': str(member.id),
                    'name': member.user.get_full_name() or member.user.username,
                    'role': member.get_role_display(),
                    'hourly_rate': float(member.hourly_rate),
                    'weekly_capacity': float(member.weekly_capacity_hours),
                    'monthly_capacity': float(member.monthly_capacity_hours)
                })
            
            # Get existing allocations
            allocations = {}
            for alloc in project.allocations.all():
                # Create keys for both weekly and monthly views
                month_key = f"{alloc.user_profile_id}_{alloc.year}_{alloc.month}"
                allocations[month_key] = float(alloc.allocated_hours)
            
            return JsonResponse({
                'success': True,
                'team_members': team_member_data,
                'allocations': allocations,
                'project_name': project.name,
                'total_hours': float(project.total_hours) if project.total_hours else 0,
                'start_date': project.start_date.isoformat() if project.start_date else None,
                'end_date': project.end_date.isoformat() if project.end_date else None
            })
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    def get_available_members_view(self, request, object_id):
        """Get team members not yet allocated to this project"""
        try:
            project = self.get_object(request, object_id)
            
            # Get members already on the project
            allocated_ids = project.allocations.values_list('user_profile_id', flat=True).distinct()
            
            # Get all company members not on the project
            available = UserProfile.objects.filter(
                company=project.company,
                status__in=['full_time', 'part_time', 'contractor']
            ).exclude(id__in=allocated_ids).select_related('user')
            
            members = []
            for member in available:
                members.append({
                    'id': str(member.id),
                    'name': member.user.get_full_name() or member.user.username,
                    'role': member.get_role_display(),
                    'hourly_rate': float(member.hourly_rate)
                })
            
            return JsonResponse({'success': True, 'members': members})
            
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    def add_member_view(self, request, object_id):
        """Add a team member to the project"""
        if request.method != 'POST':
            return JsonResponse({'error': 'Method not allowed'}, status=405)
            
        try:
            project = self.get_object(request, object_id)
            data = json.loads(request.body)
            member_id = data.get('member_id')
            
            member = UserProfile.objects.get(id=member_id, company=project.company)
            
            # Add to team_members if the field exists
            if hasattr(project, 'team_members'):
                project.team_members.add(member)
            
            # Return member data for the grid
            member_data = {
                'id': str(member.id),
                'name': member.user.get_full_name() or member.user.username,
                'role': member.get_role_display(),
                'hourly_rate': float(member.hourly_rate),
                'weekly_capacity': float(member.weekly_capacity_hours),
                'monthly_capacity': float(member.monthly_capacity_hours)
            }
            
            return JsonResponse({'success': True, 'member': member_data})
            
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    def remove_member_view(self, request, object_id):
        """Remove a team member from the project"""
        if request.method != 'POST':
            return JsonResponse({'error': 'Method not allowed'}, status=405)
            
        try:
            project = self.get_object(request, object_id)
            data = json.loads(request.body)
            member_id = data.get('member_id')
            
            # Remove allocations
            ProjectAllocation.objects.filter(
                project=project,
                user_profile_id=member_id
            ).delete()
            
            # Remove from team_members if exists
            if hasattr(project, 'team_members'):
                project.team_members.remove(member_id)
            
            return JsonResponse({'success': True})
            
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    def auto_allocate_view(self, request, object_id):
        """Auto-allocate hours evenly across team and periods"""
        if request.method != 'POST':
            return JsonResponse({'error': 'Method not allowed'}, status=405)
            
        try:
            project = self.get_object(request, object_id)
            if not project.total_hours:
                return JsonResponse({'error': 'Project has no total hours set'}, status=400)
            
            # Get team members
            member_ids = json.loads(request.body).get('member_ids', [])
            if not member_ids:
                return JsonResponse({'error': 'No team members selected'}, status=400)
            
            # Calculate periods
            periods = []
            current_date = project.start_date
            
            while current_date <= project.end_date:
                if current_date.month == 12:
                    next_month = date(current_date.year + 1, 1, 1)
                else:
                    next_month = date(current_date.year, current_date.month + 1, 1)
                
                month_end = next_month - timedelta(days=1)
                if month_end > project.end_date:
                    month_end = project.end_date
                
                periods.append({
                    'year': current_date.year,
                    'month': current_date.month,
                    'days': (month_end - current_date + timedelta(days=1)).days
                })
                
                current_date = next_month
            
            # Calculate hours per member per period
            total_days = (project.end_date - project.start_date).days + 1
            hours_per_member = float(project.total_hours) / len(member_ids)
            
            allocations = []
            for member_id in member_ids:
                member = UserProfile.objects.get(id=member_id)
                for period in periods:
                    # Proportional allocation based on days in period
                    period_hours = hours_per_member * (period['days'] / total_days)
                    
                    if period_hours > 0:
                        allocations.append({
                            'member_id': member_id,
                            'year': period['year'],
                            'month': period['month'],
                            'hours': round(period_hours, 1)
                        })
            
            return JsonResponse({'success': True, 'allocations': allocations})
            
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)}, status=500)
    
    def save_allocations_view(self, request, object_id):
        """Save all allocations from the grid"""
        if request.method != 'POST':
            return JsonResponse({'error': 'Method not allowed'}, status=405)
            
        try:
            project = self.get_object(request, object_id)
            data = json.loads(request.body)
            allocations = data.get('allocations', [])
            
            # Delete all existing allocations for this project
            ProjectAllocation.objects.filter(project=project).delete()
            
            # Create new allocations
            created = 0
            for alloc in allocations:
                try:
                    member = UserProfile.objects.get(id=alloc['member_id'])
                    hours = Decimal(str(alloc['hours']))
                    
                    if hours > 0:
                        ProjectAllocation.objects.create(
                            project=project,
                            user_profile=member,
                            year=alloc['year'],
                            month=alloc['month'],
                            allocated_hours=hours,
                            hourly_rate=member.hourly_rate
                        )
                        created += 1
                except Exception as e:
                    print(f"Error creating allocation: {e}")
            
            messages.success(request, f"Successfully saved {created} allocations")
            return JsonResponse({'success': True, 'created': created})
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            return JsonResponse({'success': False, 'error': str(e)}, status=500)


@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours', 'hourly_rate', 'total_value']
    list_filter = ['year', 'month', 'project__company', 'user_profile__role']
    search_fields = ['project__name', 'user_profile__user__first_name', 'user_profile__user__last_name']
    readonly_fields = ['total_value']
    
    def month_year(self, obj):
        return f"{calendar.month_abbr[obj.month]} {obj.year}"
    month_year.short_description = "Period"
    
    def total_value(self, obj):
        return f"${obj.total_revenue:,.2f}"
    total_value.short_description = "Value"


# Register other models
@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'monthly_amount', 'is_active']
    list_filter = ['category', 'is_active', 'company']


@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'year', 'month', 'amount']
    list_filter = ['year', 'month', 'company']


if COST_MODEL_EXISTS:
    @admin.register(Cost)
    class CostAdmin(admin.ModelAdmin):
        list_display = ['name', 'cost_type', 'amount', 'frequency', 'is_active']
        list_filter = ['cost_type', 'frequency', 'is_active', 'company']


if MONTHLY_REVENUE_EXISTS:
    @admin.register(MonthlyRevenue)
    class MonthlyRevenueAdmin(admin.ModelAdmin):
        list_display = ['client', 'project', 'year', 'month', 'revenue']
        list_filter = ['year', 'month', 'company']


admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
