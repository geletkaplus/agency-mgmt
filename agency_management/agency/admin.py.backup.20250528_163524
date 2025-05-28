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
                    'total_revenue_display', 'team_size', 'allocation_status']
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    autocomplete_fields = ['client', 'project_manager']
    
    # Use both inlines
    inlines = [ProjectTeamInline, ProjectAllocationInline]
    
    fieldsets = (
        ('Project Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status')
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date'),
            'description': 'Change dates and save to update the allocation grid below.'
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
            'all': ('admin/css/project_admin.css',)
        }
        js = ('admin/js/project_allocation.js',)
    
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
        
        if obj:
            # Always prepare allocation data if dates are set
            if obj.start_date and obj.end_date:
                from datetime import date
                from dateutil.relativedelta import relativedelta
                
                project_months = []
                current = obj.start_date.replace(day=1)
                end = obj.end_date.replace(day=1)
                
                while current <= end:
                    project_months.append({
                        'year': current.year,
                        'month': current.month,
                        'month_name': calendar.month_abbr[current.month],
                        'date': current
                    })
                    current += relativedelta(months=1)
                
                # Get team members - either assigned or all from company
                if hasattr(obj, 'team_members'):
                    team_members = obj.team_members.all()
                    if not team_members.exists():
                        # Show all company members if none assigned
                        team_members = UserProfile.objects.filter(
                            company=obj.company,
                            status__in=['full_time', 'part_time', 'contractor']
                        )
                else:
                    team_members = UserProfile.objects.filter(
                        company=obj.company,
                        status__in=['full_time', 'part_time', 'contractor']
                    )
                
                team_members = team_members.select_related('user').order_by('user__last_name')
                
                # Get existing allocations
                allocations = ProjectAllocation.objects.filter(project=obj)
                allocation_dict = {}
                for alloc in allocations:
                    key = f"{alloc.user_profile_id}_{alloc.year}_{alloc.month}"
                    allocation_dict[key] = {
                        'hours': float(alloc.allocated_hours),
                        'id': alloc.id
                    }
                
                extra_context.update({
                    'project': obj,
                    'project_months': project_months,
                    'team_members': team_members,
                    'existing_allocations': json.dumps(allocation_dict),
                    'show_allocation_grid': True
                })
            else:
                extra_context['show_allocation_grid'] = False
                messages.info(request, "Set project start and end dates to see the hour allocation grid.")
        
        return super().change_view(request, object_id, form_url, extra_context=extra_context)
    
    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        if change and ('start_date' in form.changed_data or 'end_date' in form.changed_data):
            messages.warning(request, 
                "Project dates have changed! The allocation grid has been updated. "
                "Please review and adjust team allocations as needed."
            )
    
    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path('<path:object_id>/save-allocations/', 
                 self.admin_site.admin_view(self.save_allocations_view), 
                 name='agency_project_save_allocations'),
        ]
        return custom_urls + urls
    
    def save_allocations_view(self, request, object_id):
        """Handle allocation saves via AJAX"""
        if request.method == 'POST':
            try:
                project = self.get_object(request, object_id)
                data = json.loads(request.body)
                allocations = data.get('allocations', [])
                
                # Update allocations
                for alloc_data in allocations:
                    user_profile_id = alloc_data['user_profile']
                    year = int(alloc_data['year'])
                    month = int(alloc_data['month'])
                    hours = Decimal(str(alloc_data['hours']))
                    
                    if hours > 0:
                        user_profile = UserProfile.objects.get(id=user_profile_id)
                        ProjectAllocation.objects.update_or_create(
                            project=project,
                            user_profile=user_profile,
                            year=year,
                            month=month,
                            defaults={
                                'allocated_hours': hours,
                                'hourly_rate': user_profile.hourly_rate
                            }
                        )
                    else:
                        # Delete allocation if hours is 0
                        ProjectAllocation.objects.filter(
                            project=project,
                            user_profile_id=user_profile_id,
                            year=year,
                            month=month
                        ).delete()
                
                return JsonResponse({'status': 'success'})
            except Exception as e:
                return JsonResponse({'status': 'error', 'message': str(e)})
        
        return JsonResponse({'status': 'error', 'message': 'Invalid request'})


# Simple ProjectAllocation Admin
@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours']
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
