# agency/admin.py - Improved with better team assignment and dynamic allocation grid
from django.contrib import admin
from django.db.models import Sum, Q
from django.utils.html import format_html
from django.utils.safestring import mark_safe
from django.template.response import TemplateResponse
from django.urls import path
from django.shortcuts import redirect
from django.contrib import messages
from django.http import JsonResponse
import datetime
from decimal import Decimal
import json
import calendar

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
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate_display']
    list_filter = ['role', 'status', 'company']
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


# Custom Inline for Team Members - Simple tabular style
class ProjectTeamInline(admin.TabularInline):
    model = Project.team_members.through
    extra = 5  # Show 5 empty rows
    verbose_name = "Team Member"
    verbose_name_plural = "Team Members"
    autocomplete_fields = ['userprofile']
    
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "userprofile":
            if hasattr(request, '_obj_') and request._obj_:
                kwargs["queryset"] = UserProfile.objects.filter(
                    company=request._obj_.company,
                    status__in=['full_time', 'part_time', 'contractor']
                ).select_related('user').order_by('user__last_name')
        return super().formfield_for_foreignkey(db_field, request, **kwargs)


# Custom Inline for Allocations - Grid style
class ProjectAllocationInline(admin.StackedInline):
    model = ProjectAllocation
    template = 'admin/agency/project/allocation_grid.html'
    extra = 0
    can_delete = False
    
    def has_add_permission(self, request, obj=None):
        return False


# Enhanced Project Admin
@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'start_date', 'end_date', 
                    'total_revenue_display', 'team_size', 'allocation_status', 'get_project_manager']
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    autocomplete_fields = ['client']
    
    fieldsets = (
        ('Project Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status', 'revenue_type')
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date'),
            'description': 'Set project dates to enable team allocation below.'
        }),
        ('Financials', {
            'fields': ('total_revenue', 'total_hours'),
            'description': 'Total project value and estimated hours.'
        })
    )
    
    class Media:
        css = {
            'all': ('admin/css/project_admin.css',)
        }
        js = ('admin/js/project_allocation_auth_fix.js',)
    
    def get_form(self, request, obj=None, **kwargs):
        request._obj_ = obj
        return super().get_form(request, obj, **kwargs)
    
    def total_revenue_display(self, obj):
        return f"${int(obj.total_revenue):,}"
    total_revenue_display.short_description = "Revenue"
    
    def team_size(self, obj):
        if hasattr(obj, 'team_members'):
            count = obj.team_members.count()
            return f"{count} member{'s' if count != 1 else ''}"
        return "0 members"
    team_size.short_description = "Team"
    
    def get_project_manager(self, obj):
        # Get PM from allocations with is_project_manager flag
        pm_allocation = None
        try:
            pm_allocation = obj.allocations.filter(is_project_manager=True).select_related('user_profile__user').first()
        except:
            pass
        
        if pm_allocation:
            return pm_allocation.user_profile.user.get_full_name()
        
        # Fallback to project_manager field if it exists
        if hasattr(obj, 'project_manager') and obj.project_manager:
            return obj.project_manager.get_full_name()
        
        return "-"
    get_project_manager.short_description = "Project Manager"
    
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

    def get_allocation_data_view(self, request, object_id):
        """Get team members and existing allocations"""
        try:
            project = self.get_object(request, object_id)
            
            # Get team members
            team_members = []
            if hasattr(project, 'team_members'):
                for member in project.team_members.all().select_related('user'):
                    team_members.append({
                        'id': str(member.id),
                        'name': member.user.get_full_name() or member.user.username,
                        'role': member.get_role_display(),
                        'hourly_rate': float(member.hourly_rate),
                    })
            
            # Get existing allocations
            allocations = {}
            for alloc in ProjectAllocation.objects.filter(project=project):
                # Store by different keys based on whether it has week or not
                if hasattr(alloc, 'week') and alloc.week:
                    key = f"{alloc.user_profile_id}_{alloc.year}_{alloc.month}_{alloc.week}"
                else:
                    key = f"{alloc.user_profile_id}_{alloc.year}_{alloc.month}_1"
                allocations[key] = float(alloc.allocated_hours)
                
                # Also store PM status
                if hasattr(alloc, 'is_project_manager') and alloc.is_project_manager:
                    allocations[f"{alloc.user_profile_id}_pm"] = True
            
            return JsonResponse({
                'team_members': team_members,
                'allocations': allocations
            })
        except Exception as e:
            import traceback
            traceback.print_exc()
            return JsonResponse({'error': str(e)}, status=400)
    
    def get_available_members_view(self, request, object_id):
        """Get available team members not yet on the project"""
        try:
            project = self.get_object(request, object_id)
            
            # Get current team member IDs
            current_member_ids = []
            if hasattr(project, 'team_members'):
                current_member_ids = list(project.team_members.values_list('id', flat=True))
            
            # Get all company members not on the project
            members = UserProfile.objects.filter(
                company=project.company,
                status__in=['full_time', 'part_time', 'contractor']
            ).exclude(
                id__in=current_member_ids
            ).select_related('user')
            
            member_list = []
            for member in members:
                member_list.append({
                    'id': str(member.id),
                    'name': member.user.get_full_name() or member.user.username,
                    'role': member.get_role_display()
                })
            
            return JsonResponse({'members': member_list})
        except Exception as e:
            import traceback
            traceback.print_exc()
            return JsonResponse({'error': str(e)}, status=400)
    
    def add_member_view(self, request, object_id):
        """Add a team member to the project"""
        if request.method == 'POST':
            try:
                project = self.get_object(request, object_id)
                data = json.loads(request.body)
                member_id = data.get('member_id')
                
                member = UserProfile.objects.get(id=member_id, company=project.company)
                if hasattr(project, 'team_members'):
                    project.team_members.add(member)
                
                return JsonResponse({'success': True})
            except Exception as e:
                import traceback
                traceback.print_exc()
                return JsonResponse({'error': str(e)}, status=400)
        
        return JsonResponse({'error': 'Invalid request'}, status=400)
    
    def remove_member_view(self, request, object_id):
        """Remove a team member from the project"""
        if request.method == 'POST':
            try:
                project = self.get_object(request, object_id)
                data = json.loads(request.body)
                member_id = data.get('member_id')
                
                member = UserProfile.objects.get(id=member_id)
                if hasattr(project, 'team_members'):
                    project.team_members.remove(member)
                
                # Also remove their allocations
                ProjectAllocation.objects.filter(
                    project=project,
                    user_profile=member
                ).delete()
                
                return JsonResponse({'success': True})
            except Exception as e:
                import traceback
                traceback.print_exc()
                return JsonResponse({'error': str(e)}, status=400)
        
        return JsonResponse({'error': 'Invalid request'}, status=400)
    
    def save_allocations_view(self, request, object_id):
        """Handle allocation saves via AJAX"""
        if request.method == 'POST':
            try:
                project = self.get_object(request, object_id)
                data = json.loads(request.body)
                allocations = data.get('allocations', [])
                
                # First pass - identify PM
                pm_member_id = None
                for alloc in allocations:
                    if alloc.get('is_pm'):
                        pm_member_id = alloc.get('member_id')
                        break
                
                # Clear existing allocations
                ProjectAllocation.objects.filter(project=project).delete()
                
                # Second pass - create allocations
                for alloc in allocations:
                    if 'is_pm' in alloc:
                        continue  # Skip PM-only entries
                    
                    member_id = alloc.get('member_id')
                    year = int(alloc.get('year', 0))
                    month = int(alloc.get('month', 0))
                    week = alloc.get('week')
                    hours = float(alloc.get('hours', 0))
                    
                    if member_id and year and month:
                        try:
                            member = UserProfile.objects.get(id=member_id)
                            
                            allocation = ProjectAllocation(
                                project=project,
                                user_profile=member,
                                year=year,
                                month=month,
                                allocated_hours=Decimal(str(hours)),
                                hourly_rate=member.hourly_rate,
                            )
                            
                            # Set PM status if applicable
                            if hasattr(allocation, 'is_project_manager'):
                                allocation.is_project_manager = (str(member_id) == str(pm_member_id))
                            
                            # Only set week if it exists
                            if week and hasattr(allocation, 'week'):
                                allocation.week = int(week)
                            
                            allocation.save()
                            
                        except Exception as e:
                            print(f"Error creating allocation: {e}")
                            import traceback
                            traceback.print_exc()
                            continue
                
                return JsonResponse({'status': 'success'})
            except Exception as e:
                print(f"Error in save_allocations_view: {e}")
                import traceback
                traceback.print_exc()
                return JsonResponse({'status': 'error', 'message': str(e)}, status=400)
        
        return JsonResponse({'status': 'error', 'message': 'Invalid request'}, status=400)

@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours']
    ordering = ['-year', '-month', 'project__name']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name', 'user_profile__user__first_name']
    
    def month_year(self, obj):
        return f"{calendar.month_abbr[obj.month]} {obj.year}"


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
