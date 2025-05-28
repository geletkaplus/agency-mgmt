# Enhanced admin configuration for project allocations
# Add this to your admin.py or replace relevant sections

from django.contrib import admin
from django.db.models import Sum, F, Q
from django.utils.html import format_html
from django import forms
from decimal import Decimal

class ProjectAllocationInline(admin.TabularInline):
    model = ProjectAllocation
    extra = 1
    fields = ['user_profile', 'year', 'month', 'allocated_hours', 
              'hourly_rate', 'billable_rate_override', 'notes']
    autocomplete_fields = ['user_profile']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.select_related('user_profile__user')

class ProjectAdminForm(forms.ModelForm):
    class Meta:
        model = Project
        fields = '__all__'
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.instance.pk:
            # Show calculated values in help text
            self.fields['billable_rate'].help_text = format_html(
                'Current rate: ${}/hr<br>Calculated hours: {:.1f}<br>Allocated: {:.1f} hrs',
                self.instance.billable_rate,
                self.instance.calculated_hours or 0,
                self.instance.allocated_hours
            )

@admin.register(Project)
class EnhancedProjectAdmin(admin.ModelAdmin):
    form = ProjectAdminForm
    list_display = ['name', 'client', 'status', 'revenue_type', 
                    'total_revenue', 'billable_rate', 'calculated_hours_display',
                    'allocation_progress', 'start_date', 'end_date']
    list_filter = ['status', 'revenue_type', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    inlines = [ProjectAllocationInline]
    
    fieldsets = (
        ('Basic Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status', 'revenue_type')
        }),
        ('Financial Details', {
            'fields': ('total_revenue', 'billable_rate', 'calculated_hours', 'total_hours'),
            'description': 'Total revenue ÷ Billable rate = Calculated hours'
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date')
        }),
        ('Management', {
            'fields': ('project_manager',)
        })
    )
    
    def calculated_hours_display(self, obj):
        if obj.calculated_hours:
            return format_html(
                '{:.1f} hrs<br><small>${:.0f}/hr</small>',
                obj.calculated_hours,
                obj.billable_rate
            )
        return '-'
    calculated_hours_display.short_description = 'Calculated Hours'
    
    def allocation_progress(self, obj):
        allocated = float(obj.allocated_hours)
        total = float(obj.calculated_hours or obj.total_hours or 0)
        
        if total > 0:
            percentage = (allocated / total) * 100
            color = 'green' if percentage >= 80 else 'orange' if percentage >= 50 else 'red'
            return format_html(
                '<div style="width:100px; background:#ddd; border-radius:3px;">'
                '<div style="width:{}%; background:{}; color:white; text-align:center; border-radius:3px;">'
                '{:.0f}%</div></div>',
                min(percentage, 100), color, percentage
            )
        return '-'
    allocation_progress.short_description = 'Allocation'

# Quick allocation action
@admin.action(description='Quick allocate team to selected projects')
def quick_allocate_team(modeladmin, request, queryset):
    # This would open a form to quickly allocate team members
    # For now, just show a message
    modeladmin.message_user(
        request,
        f"Quick allocation for {queryset.count()} projects - Feature coming soon!"
    )
