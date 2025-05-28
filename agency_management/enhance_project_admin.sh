#!/bin/bash

# Enhanced Project Admin Script
# This script adds inline allocations, permission controls, and dashboard filters

echo "========================================="
echo "Enhanced Project Admin & Dashboard"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_action() {
    echo -e "${BLUE}[ACTION]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    echo "Error: manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Backup current admin.py
print_status "Backing up current admin.py..."
cp agency/admin.py agency/admin.py.backup.$(date +%Y%m%d_%H%M%S)

# Step 2: Create enhanced admin.py with inline allocations and permissions
print_status "Creating enhanced admin.py with permissions..."

cat > agency/admin.py << 'EOF'
# agency/admin.py - Enhanced with inline allocations and permission controls
from django.contrib import admin
from django.db.models import Sum, Q, F
from django.utils.html import format_html
from django import forms
from django.contrib.auth.models import User
from django.utils import timezone
from decimal import Decimal
import calendar

# Import models
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

# Custom inline for Project Allocations
class ProjectAllocationInline(admin.TabularInline):
    model = ProjectAllocation
    extra = 3  # Show 3 empty rows for new allocations
    fields = ['user_profile', 'year', 'month', 'allocated_hours', 'hourly_rate']
    autocomplete_fields = ['user_profile']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.select_related('user_profile__user', 'project')
    
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "user_profile":
            # Only show active team members from the same company
            if hasattr(request, '_obj_') and request._obj_:
                kwargs["queryset"] = UserProfile.objects.filter(
                    company=request._obj_.company,
                    status__in=['full_time', 'part_time', 'contractor']
                ).select_related('user')
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

# Company Admin
@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'created_at']
    search_fields = ['name', 'code']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_superuser:
            return qs
        # Non-superusers only see their company
        if hasattr(request.user, 'profile'):
            return qs.filter(id=request.user.profile.company_id)
        return qs.none()

# UserProfile Admin with permission controls
@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'company', 'role', 'status', 'display_hourly_rate', 'display_salary']
    list_filter = ['role', 'status', 'company']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']
    autocomplete_fields = ['user']
    
    def display_hourly_rate(self, obj):
        if self.has_payroll_access(self.request):
            return f"${obj.hourly_rate:.2f}"
        return "---"
    display_hourly_rate.short_description = "Hourly Rate"
    
    def display_salary(self, obj):
        if self.has_payroll_access(self.request) and obj.annual_salary:
            return f"${obj.annual_salary:,.0f}"
        return "---"
    display_salary.short_description = "Annual Salary"
    
    def has_payroll_access(self, request):
        return request.user.is_superuser
    
    def get_fields(self, request, obj=None):
        fields = ['user', 'company', 'role', 'status', 'start_date', 'end_date',
                  'weekly_capacity_hours', 'utilization_target']
        if request.user.is_superuser:
            fields.extend(['hourly_rate', 'annual_salary'])
        return fields
    
    def changelist_view(self, request, extra_context=None):
        # Store request for use in display methods
        self.request = request
        return super().changelist_view(request, extra_context)

# Client Admin
@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager', 'project_count', 'total_revenue']
    list_filter = ['status', 'company']
    search_fields = ['name']
    autocomplete_fields = ['account_manager']
    
    def project_count(self, obj):
        return obj.projects.count()
    project_count.short_description = "Projects"
    
    def total_revenue(self, obj):
        total = obj.projects.aggregate(total=Sum('total_revenue'))['total'] or 0
        return format_html('${:,.0f}', total)
    total_revenue.short_description = "Total Revenue"

# Enhanced Project Admin with inline allocations
@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'revenue_type', 'start_date', 
                    'end_date', 'formatted_revenue', 'allocation_progress']
    list_filter = ['status', 'revenue_type', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    autocomplete_fields = ['client', 'project_manager']
    inlines = [ProjectAllocationInline]
    
    fieldsets = (
        ('Project Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status', 'revenue_type')
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date')
        }),
        ('Financials', {
            'fields': ('total_revenue', 'total_hours'),
            'classes': ('wide',),
        }),
        ('Management', {
            'fields': ('project_manager',),
        }),
    )
    
    # Only superusers can edit billable_rate
    def get_fieldsets(self, request, obj=None):
        fieldsets = list(self.fieldsets)
        if request.user.is_superuser:
            # Insert billable rate in Financials section
            for idx, (title, field_dict) in enumerate(fieldsets):
                if title == 'Financials':
                    fields = list(field_dict['fields'])
                    if hasattr(self.model, 'billable_rate'):
                        fields.insert(1, 'billable_rate')
                        fields.append('calculated_hours')
                    fieldsets[idx] = (title, {**field_dict, 'fields': tuple(fields)})
        return fieldsets
    
    def formatted_revenue(self, obj):
        return format_html('${:,.0f}', obj.total_revenue)
    formatted_revenue.short_description = "Total Revenue"
    formatted_revenue.admin_order_field = 'total_revenue'
    
    def allocation_progress(self, obj):
        allocated = obj.allocations.aggregate(total=Sum('allocated_hours'))['total'] or 0
        total = obj.total_hours or 0
        
        if hasattr(obj, 'calculated_hours') and obj.calculated_hours:
            total = obj.calculated_hours
        
        if total > 0:
            percentage = (float(allocated) / float(total)) * 100
            color = 'green' if percentage >= 80 else 'orange' if percentage >= 50 else 'red'
            return format_html(
                '<div style="width:100px; background:#ddd; border-radius:3px; position:relative;">'
                '<div style="width:{}%; background:{}; color:white; text-align:center; '
                'border-radius:3px; padding:2px; min-width:30px;">{:.0f}%</div></div>',
                min(percentage, 100), color, percentage
            )
        return format_html('<span style="color:#999;">No hours set</span>')
    allocation_progress.short_description = "Allocated"
    
    def get_form(self, request, obj=None, **kwargs):
        # Store obj on request for use in inline
        request._obj_ = obj
        return super().get_form(request, obj, **kwargs)
    
    def save_formset(self, request, form, formset, change):
        instances = formset.save(commit=False)
        for instance in instances:
            # Auto-fill the current year/month if not set
            if not instance.year:
                instance.year = timezone.now().year
            if not instance.month:
                instance.month = timezone.now().month
            instance.save()
        formset.save_m2m()

# ProjectAllocation Admin
@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours', 
                    'display_hourly_rate', 'allocation_value']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name', 'user_profile__user__first_name', 
                     'user_profile__user__last_name']
    autocomplete_fields = ['project', 'user_profile']
    
    def month_year(self, obj):
        month_name = calendar.month_abbr[obj.month]
        return f"{month_name} {obj.year}"
    month_year.short_description = "Period"
    month_year.admin_order_field = 'year'
    
    def display_hourly_rate(self, obj):
        if self.request.user.is_superuser:
            return f"${obj.hourly_rate:.2f}"
        return "---"
    display_hourly_rate.short_description = "Rate"
    
    def allocation_value(self, obj):
        if self.request.user.is_superuser:
            value = obj.allocated_hours * obj.hourly_rate
            return format_html('${:,.0f}', value)
        return "---"
    allocation_value.short_description = "Value"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)
    
    def get_fields(self, request, obj=None):
        fields = ['project', 'user_profile', 'year', 'month', 'allocated_hours']
        if request.user.is_superuser:
            fields.append('hourly_rate')
        return fields

# Cost Admin (if model exists)
if COST_MODEL_EXISTS:
    @admin.register(Cost)
    class CostAdmin(admin.ModelAdmin):
        list_display = ['name', 'cost_type', 'display_amount', 'frequency', 
                        'is_contractor', 'is_active']
        list_filter = ['cost_type', 'frequency', 'is_contractor', 'is_active', 'company']
        search_fields = ['name', 'description', 'vendor']
        
        def display_amount(self, obj):
            if self.request.user.is_superuser:
                return f"${obj.amount:,.2f}"
            elif obj.cost_type != 'payroll':
                return f"${obj.amount:,.2f}"
            return "---"
        display_amount.short_description = "Amount"
        
        def changelist_view(self, request, extra_context=None):
            self.request = request
            return super().changelist_view(request, extra_context)
        
        def get_fields(self, request, obj=None):
            if request.user.is_superuser:
                return super().get_fields(request, obj)
            # Hide payroll-related fields for non-superusers
            fields = ['company', 'name', 'cost_type', 'description', 'vendor',
                      'frequency', 'start_date', 'end_date', 'is_contractor',
                      'project', 'is_billable', 'is_active']
            if obj and obj.cost_type != 'payroll':
                fields.insert(5, 'amount')
            return fields

# Legacy model admins
@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'display_amount', 'is_active']
    list_filter = ['category', 'is_active', 'company']
    
    def display_amount(self, obj):
        if self.request.user.is_superuser or obj.category != 'payroll':
            return f"${obj.monthly_amount:,.2f}/mo"
        return "---"
    display_amount.short_description = "Amount"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)

@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'month_year', 'display_amount']
    list_filter = ['year', 'month', 'company']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"
    month_year.short_description = "Period"
    
    def display_amount(self, obj):
        if self.request.user.is_superuser:
            return f"${obj.amount:,.2f}"
        return "---"
    display_amount.short_description = "Amount"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)

# Customize admin site headers
admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
EOF

print_status "Enhanced admin.py created!"

# Step 3: Update dashboard template with monthly filter and number formatting
print_status "Updating dashboard template with filters and formatting..."

# Find dashboard template
if [ -f "templates/dashboard.html" ]; then
    DASHBOARD_PATH="templates/dashboard.html"
elif [ -f "agency/templates/dashboard.html" ]; then
    DASHBOARD_PATH="agency/templates/dashboard.html"
else
    DASHBOARD_PATH="templates/dashboard.html"
fi

# Backup dashboard
cp "$DASHBOARD_PATH" "$DASHBOARD_PATH.backup.$(date +%Y%m%d_%H%M%S)"

# Add month filter to dashboard
print_status "Adding month filter to revenue chart..."

# Create a Python script to update the dashboard
cat > /tmp/update_dashboard.py << 'EOF'
import re
import sys

# Read the dashboard file
with open(sys.argv[1], 'r') as f:
    content = f.read()

# Add month filter to the chart controls
chart_controls = '''<div class="flex space-x-4">
                            <select id="monthSelect" class="border border-gray-300 rounded-md px-3 py-2">
                                <option value="all" selected>All Months</option>
                                <option value="1">January</option>
                                <option value="2">February</option>
                                <option value="3">March</option>
                                <option value="4">April</option>
                                <option value="5">May</option>
                                <option value="6">June</option>
                                <option value="7">July</option>
                                <option value="8">August</option>
                                <option value="9">September</option>
                                <option value="10">October</option>
                                <option value="11">November</option>
                                <option value="12">December</option>
                            </select>
                            <select id="yearSelect" class="border border-gray-300 rounded-md px-3 py-2">
                                <option value="2024">2024</option>
                                <option value="2025" selected>2025</option>
                                <option value="2026">2026</option>
                            </select>'''

# Replace the year select with month + year selects
content = re.sub(
    r'<select id="yearSelect"[^>]*>.*?</select>',
    chart_controls,
    content,
    flags=re.DOTALL
)

# Write back
with open(sys.argv[1], 'w') as f:
    f.write(content)

print("Dashboard updated with month filter")
EOF

python3 /tmp/update_dashboard.py "$DASHBOARD_PATH"

# Step 4: Update views.py to hide payroll data from non-superusers
print_status "Updating views.py with permission controls..."

# Create views patch
cat > /tmp/views_permissions.patch << 'EOF'
# In your dashboard view, add permission checks:

        # Monthly costs calculation
        payroll_costs = Decimal('0')
        contractor_costs = Decimal('0')
        other_costs = Decimal('0')
        
        # Only show payroll costs to superusers
        if request.user.is_superuser:
            # Calculate payroll costs from team members
            team_members = UserProfile.objects.filter(company=company, status='full_time')
            for member in team_members:
                payroll_costs += member.monthly_salary_cost
        
        # ... rest of cost calculations ...
        
        # In context, conditionally show payroll
        context = {
            # ... other context ...
            'payroll_costs': payroll_costs if request.user.is_superuser else None,
            'show_payroll': request.user.is_superuser,
            # ...
        }

# Also update the revenue_chart_data view to respect permissions:

@login_required
def revenue_chart_data(request):
    # ... existing code ...
    
    # Calculate operating expenses for each month
    for month in range(1, 13):
        if request.user.is_superuser:
            monthly_data[month]['expenses'] = float(
                calculate_monthly_operating_costs(company, year, month)
            )
        else:
            # Only show non-payroll costs
            monthly_data[month]['expenses'] = float(
                calculate_monthly_operating_costs(company, year, month, exclude_payroll=True)
            )
EOF

print_status "Views permission patch created at: /tmp/views_permissions.patch"

# Step 5: Create custom templatetags for number formatting
print_status "Creating templatetags for number formatting..."

mkdir -p agency/templatetags
touch agency/templatetags/__init__.py

cat > agency/templatetags/agency_filters.py << 'EOF'
from django import template
from django.contrib.humanize.templatetags.humanize import intcomma

register = template.Library()

@register.filter
def currency(value):
    """Format value as currency with commas"""
    try:
        return f"${intcomma(int(float(value)))}"
    except (ValueError, TypeError):
        return "$0"

@register.filter
def currency_decimal(value):
    """Format value as currency with commas and decimals"""
    try:
        return f"${intcomma(round(float(value), 2))}"
    except (ValueError, TypeError):
        return "$0.00"

@register.filter
def number_comma(value):
    """Format number with commas"""
    try:
        return intcomma(int(float(value)))
    except (ValueError, TypeError):
        return "0"
EOF

print_status "Template filters created!"

# Step 6: Create summary of changes
echo ""
echo "========================================="
echo "Project Admin Enhancements Complete!"
echo "========================================="
echo ""
print_status "What was added:"
echo "  ✓ Inline allocation management on project admin page"
echo "  ✓ Add multiple team members with hours directly"
echo "  ✓ Billable rate field only visible to superusers"
echo "  ✓ Payroll data hidden from non-superusers"
echo "  ✓ Monthly filter added to dashboard"
echo "  ✓ Number formatting with commas"
echo ""
print_action "Permission Summary:"
echo "  Superusers can see:"
echo "    - All financial data including payroll"
echo "    - Billable rates on projects"
echo "    - Hourly rates and salaries"
echo "    - Full cost breakdowns"
echo ""
echo "  Regular users can see:"
echo "    - Project information"
echo "    - Client data"
echo "    - Non-payroll expenses"
echo "    - Team capacity (not rates)"
echo ""
print_action "Next steps:"
echo "  1. Apply the views permission patch from /tmp/views_permissions.patch"
echo "  2. Update dashboard template to use {% load agency_filters %}"
echo "  3. Add 'django.contrib.humanize' to INSTALLED_APPS"
echo "  4. Test with both superuser and regular user accounts"
echo ""
print_status "Usage:"
echo "  - In templates: {{ value|currency }} for $1,234"
echo "  - In templates: {{ value|currency_decimal }} for $1,234.56"
echo "  - Monthly filter on dashboard for focused views"
echo ""

# Ask if user wants to restart server
read -p "Would you like to restart the development server? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Restarting development server..."
    python manage.py runserver
fi