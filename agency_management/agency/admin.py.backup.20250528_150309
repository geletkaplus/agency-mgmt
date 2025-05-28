# agency/admin.py - Updated with MonthlyRevenue removed from admin
from django.contrib import admin
from django.db.models import Sum

# Import models that definitely exist
from .models import (
    Company, UserProfile, Client, Project, 
    ProjectAllocation, Expense, ContractorExpense
)

# Try to import new models if they exist
try:
    from .models import Cost, CapacitySnapshot
    COST_MODEL_EXISTS = True
except ImportError:
    COST_MODEL_EXISTS = False

@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'created_at']
    search_fields = ['name', 'code']

@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate']
    list_filter = ['role', 'status', 'company']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']

@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager']
    list_filter = ['status', 'company']
    search_fields = ['name']

@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    # Check if revenue_type field exists
    try:
        list_display = ['name', 'client', 'status', 'revenue_type', 'start_date', 'end_date', 'total_revenue']
        list_filter = ['status', 'revenue_type', 'project_type', 'company']
    except:
        list_display = ['name', 'client', 'status', 'start_date', 'end_date', 'total_revenue']
        list_filter = ['status', 'project_type', 'company']
    
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'

@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours', 'hourly_rate']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

# NOTE: MonthlyRevenue removed from admin - data is managed through Projects

# Register Cost model if it exists
if COST_MODEL_EXISTS:
    @admin.register(Cost)
    class CostAdmin(admin.ModelAdmin):
        list_display = ['name', 'cost_type', 'amount', 'frequency', 'is_contractor', 'is_active']
        list_filter = ['cost_type', 'frequency', 'is_contractor', 'is_active', 'company']
        search_fields = ['name', 'description', 'vendor']
        
        fieldsets = (
            ('Basic Information', {
                'fields': ('company', 'name', 'cost_type', 'description', 'vendor')
            }),
            ('Cost Details', {
                'fields': ('amount', 'frequency', 'start_date', 'end_date')
            }),
            ('Assignment & Flags', {
                'fields': ('is_contractor', 'project', 'is_billable', 'is_active')
            })
        )

    @admin.register(CapacitySnapshot)
    class CapacitySnapshotAdmin(admin.ModelAdmin):
        list_display = ['company', 'month_year', 'utilization_rate']
        list_filter = ['year', 'month', 'company']
        
        def month_year(self, obj):
            return f"{obj.year}-{obj.month:02d}"

# Legacy models
@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'monthly_amount', 'is_active']
    list_filter = ['category', 'is_active', 'company']

@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'month_year', 'amount']
    list_filter = ['year', 'month', 'company']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"

admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
