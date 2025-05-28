#!/bin/bash

# Create Complete Admin Script
# This script creates a full admin.py with smart allocations

echo "========================================="
echo "Creating Complete Admin.py"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    echo "Error: manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Create the complete admin.py
print_status "Creating complete admin.py with smart allocations..."

cat > agency/admin.py << 'EOF'
# agency/admin.py - Complete admin with smart allocations
from django.contrib import admin
from django.db.models import Sum, Q
from django.utils.html import format_html
from django.utils.safestring import mark_safe
from django.template.response import TemplateResponse
from django.urls import path
from django.shortcuts import redirect
from django.contrib import messages
from decimal import Decimal
import json

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

# Try to import MonthlyRevenue
try:
    from .models import MonthlyRevenue
    MONTHLY_REVENUE_EXISTS = True
except ImportError:
    MONTHLY_REVENUE_EXISTS = False


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


# UserProfile Admin
@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ['user', 'company', 'role', 'status', 'hourly_rate_display']
    list_filter = ['role', 'status', 'company']
    search_fields = ['user__username', 'user__first_name', 'user__last_name']
    autocomplete_fields = ['user']
    
    def hourly_rate_display(self, obj):
        if self.request.user.is_superuser:
            return f"${obj.hourly_rate:.2f}"
        return "---"
    hourly_rate_display.short_description = "Hourly Rate"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)
    
    def get_fields(self, request, obj=None):
        fields = ['user', 'company', 'role', 'status', 'start_date', 'end_date',
                  'weekly_capacity_hours', 'utilization_target']
        if request.user.is_superuser:
            fields.extend(['hourly_rate', 'annual_salary'])
        return fields


# Client Admin
@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager', 'project_count']
    list_filter = ['status', 'company']
    search_fields = ['name']
    autocomplete_fields = ['account_manager']
    
    def project_count(self, obj):
        return obj.projects.count()
    project_count.short_description = "Projects"


# Smart Project Allocation Inline
class SmartProjectAllocationInline(admin.StackedInline):
    """Custom inline that shows allocation grid"""
    model = ProjectAllocation
    template = 'admin/agency/project/allocation_inline.html'
    extra = 0
    can_delete = False
    
    def has_add_permission(self, request, obj=None):
        return False


# Project Admin with Smart Allocations
@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    # Dynamic list_display based on available fields
    base_list_display = ['name', 'client', 'status', 'start_date', 'end_date', 
                         'total_revenue_display', 'allocation_status']
    
    def get_list_display(self, request):
        list_display = list(self.base_list_display)
        # Add revenue_type if it exists
        try:
            self.model._meta.get_field('revenue_type')
            # Insert after status
            idx = list_display.index('status') + 1
            list_display.insert(idx, 'revenue_type')
        except:
            pass
        return list_display
    
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    autocomplete_fields = ['client', 'project_manager']
    inlines = [SmartProjectAllocationInline]
    
    fieldsets = (
        ('Project Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status')
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date')
        }),
        ('Financials', {
            'fields': ('total_revenue', 'total_hours'),
        }),
        ('Management', {
            'fields': ('project_manager',)
        })
    )
    
    def get_fieldsets(self, request, obj=None):
        fieldsets = list(self.fieldsets)
        
        # Add revenue_type if it exists
        if hasattr(self.model, 'revenue_type'):
            for idx, (title, field_dict) in enumerate(fieldsets):
                if title == 'Project Information':
                    fields = list(field_dict['fields'])
                    fields.append('revenue_type')
                    fieldsets[idx] = (title, {**field_dict, 'fields': tuple(fields)})
        
        # Add billable_rate for superusers if it exists
        if request.user.is_superuser and hasattr(self.model, 'billable_rate'):
            for idx, (title, field_dict) in enumerate(fieldsets):
                if title == 'Financials':
                    fields = list(field_dict['fields'])
                    fields.insert(1, 'billable_rate')
                    if hasattr(self.model, 'calculated_hours'):
                        fields.append('calculated_hours')
                    fieldsets[idx] = (title, {**field_dict, 'fields': tuple(fields)})
        
        return fieldsets
    
    def total_revenue_display(self, obj):
        return f"${int(obj.total_revenue):,}"
    total_revenue_display.short_description = "Total Revenue"
    total_revenue_display.admin_order_field = 'total_revenue'
    
    def allocation_status(self, obj):
        allocated = obj.allocations.aggregate(total=Sum('allocated_hours'))['total'] or Decimal('0')
        total = obj.total_hours or Decimal('0')
        
        if hasattr(obj, 'calculated_hours') and obj.calculated_hours:
            total = obj.calculated_hours
        
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
        
        # Get the project
        obj = self.get_object(request, object_id)
        if obj:
            # Calculate project months
            project_months = []
            if obj.start_date and obj.end_date:
                from datetime import date
                from dateutil.relativedelta import relativedelta
                
                current = obj.start_date.replace(day=1)
                end = obj.end_date.replace(day=1)
                
                while current <= end:
                    project_months.append((current.year, current.month, current))
                    current += relativedelta(months=1)
            
            # Get team members
            team_members = UserProfile.objects.filter(
                company=obj.company,
                status__in=['full_time', 'part_time', 'contractor']
            ).select_related('user').order_by('user__last_name', 'user__first_name')
            
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
            })
        
        return super().change_view(request, object_id, form_url, extra_context=extra_context)
    
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
                
                # Process allocations
                for alloc_data in allocations:
                    user_profile_id = alloc_data['user_profile']
                    year = int(alloc_data['year'])
                    month = int(alloc_data['month'])
                    hours = Decimal(str(alloc_data['hours']))
                    
                    # Get user profile
                    user_profile = UserProfile.objects.get(id=user_profile_id)
                    
                    # Update or create allocation
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
                
                # Delete allocations with 0 hours
                ProjectAllocation.objects.filter(
                    project=project,
                    allocated_hours=0
                ).delete()
                
                messages.success(request, 'Allocations saved successfully!')
                return JsonResponse({'status': 'success'})
                
            except Exception as e:
                return JsonResponse({'status': 'error', 'message': str(e)})
        
        return JsonResponse({'status': 'error', 'message': 'Invalid request'})


# Project Allocation Admin
@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours', 'hourly_rate_display']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name', 'user_profile__user__first_name']
    autocomplete_fields = ['project', 'user_profile']
    
    def month_year(self, obj):
        import calendar
        month_name = calendar.month_abbr[obj.month]
        return f"{month_name} {obj.year}"
    month_year.short_description = "Period"
    
    def hourly_rate_display(self, obj):
        if self.request.user.is_superuser:
            return f"${obj.hourly_rate:.2f}"
        return "---"
    hourly_rate_display.short_description = "Rate"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)


# Cost Admin (if model exists)
if COST_MODEL_EXISTS:
    @admin.register(Cost)
    class CostAdmin(admin.ModelAdmin):
        list_display = ['name', 'cost_type', 'amount_display', 'frequency', 'is_contractor', 'is_active']
        list_filter = ['cost_type', 'frequency', 'is_contractor', 'is_active', 'company']
        search_fields = ['name', 'description', 'vendor']
        
        def amount_display(self, obj):
            if self.request.user.is_superuser or obj.cost_type != 'payroll':
                return f"${obj.amount:,.2f}"
            return "---"
        amount_display.short_description = "Amount"
        
        def changelist_view(self, request, extra_context=None):
            self.request = request
            return super().changelist_view(request, extra_context)


# Capacity Snapshot Admin (if model exists)
if COST_MODEL_EXISTS:
    @admin.register(CapacitySnapshot)
    class CapacitySnapshotAdmin(admin.ModelAdmin):
        list_display = ['company', 'month_year', 'utilization_rate']
        list_filter = ['year', 'month', 'company']
        
        def month_year(self, obj):
            return f"{obj.year}-{obj.month:02d}"


# Monthly Revenue Admin (if model exists)
if MONTHLY_REVENUE_EXISTS:
    @admin.register(MonthlyRevenue)
    class MonthlyRevenueAdmin(admin.ModelAdmin):
        list_display = ['client', 'project', 'year', 'month', 'revenue', 'revenue_type']
        list_filter = ['year', 'month', 'revenue_type', 'company']
        search_fields = ['client__name', 'project__name']


# Legacy models
@admin.register(Expense)
class ExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'category', 'monthly_amount_display', 'is_active']
    list_filter = ['category', 'is_active', 'company']
    
    def monthly_amount_display(self, obj):
        if self.request.user.is_superuser or obj.category != 'payroll':
            return f"${obj.monthly_amount:,.2f}/mo"
        return "---"
    monthly_amount_display.short_description = "Amount"
    
    def changelist_view(self, request, extra_context=None):
        self.request = request
        return super().changelist_view(request, extra_context)


@admin.register(ContractorExpense)
class ContractorExpenseAdmin(admin.ModelAdmin):
    list_display = ['name', 'month_year', 'amount']
    list_filter = ['year', 'month', 'company']
    
    def month_year(self, obj):
        return f"{obj.year}-{obj.month:02d}"


# Customize admin site
admin.site.site_header = "Agency Management Admin"
admin.site.site_title = "Agency Management"
admin.site.index_title = "Welcome to Agency Management"
EOF

print_status "Complete admin.py created!"

# Step 2: Check if dateutil is installed
print_status "Installing python-dateutil if needed..."
pip install python-dateutil

# Step 3: Create the allocation template
print_status "Creating allocation template..."

mkdir -p templates/admin/agency/project
cat > templates/admin/agency/project/allocation_inline.html << 'EOF'
{% load i18n admin_urls static %}
<div class="module" id="allocation-grid">
    <h2>Team Allocations</h2>
    
    {% if project and project.start_date and project.end_date %}
    <div class="allocation-info" style="margin: 10px 0; padding: 10px; background: #f0f0f0; border-radius: 4px;">
        <p style="margin: 5px 0;">
            <strong>Project Duration:</strong> 
            {{ project.start_date|date:"M Y" }} - {{ project.end_date|date:"M Y" }}
            ({{ project_months|length }} months)
        </p>
        {% if project.total_hours %}
        <p style="margin: 5px 0;">
            <strong>Total Hours:</strong> {{ project.total_hours|floatformat:0 }}
            | <strong>Allocated:</strong> <span id="total-allocated">0</span>
            | <strong>Remaining:</strong> <span id="remaining-hours">{{ project.total_hours|floatformat:0 }}</span>
        </p>
        {% endif %}
    </div>
    
    <div class="allocation-grid" style="overflow-x: auto;">
        <table class="allocation-table" style="width: 100%; border-collapse: collapse;">
            <thead>
                <tr style="background: #79aec8;">
                    <th style="padding: 10px; text-align: left; color: white; position: sticky; left: 0; background: #79aec8; z-index: 10; min-width: 200px;">
                        Team Member
                    </th>
                    {% for year, month, date in project_months %}
                    <th style="padding: 10px; text-align: center; color: white; min-width: 80px;">
                        {{ date|date:"M" }}<br>{{ year }}
                    </th>
                    {% endfor %}
                    <th style="padding: 10px; text-align: center; color: white; min-width: 80px;">
                        Total
                    </th>
                </tr>
            </thead>
            <tbody>
                {% for member in team_members %}
                <tr class="allocation-row" data-member-id="{{ member.id }}">
                    <td style="padding: 10px; border: 1px solid #ddd; position: sticky; left: 0; background: white; z-index: 5;">
                        <strong>{{ member.user.get_full_name|default:member.user.username }}</strong><br>
                        <small style="color: #666;">{{ member.get_role_display }} • ${{ member.hourly_rate|floatformat:0 }}/hr</small>
                    </td>
                    {% for year, month, date in project_months %}
                    <td style="padding: 5px; border: 1px solid #ddd; text-align: center;">
                        <input type="number" 
                               class="allocation-input"
                               data-member="{{ member.id }}"
                               data-year="{{ year }}"
                               data-month="{{ month }}"
                               data-rate="{{ member.hourly_rate }}"
                               value="0"
                               min="0"
                               step="0.5"
                               style="width: 60px; text-align: center;">
                    </td>
                    {% endfor %}
                    <td style="padding: 10px; border: 1px solid #ddd; text-align: center; font-weight: bold;">
                        <span class="member-total" data-member="{{ member.id }}">0</span>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
            <tfoot>
                <tr style="background: #f5f5f5; font-weight: bold;">
                    <td style="padding: 10px; border: 1px solid #ddd;">Monthly Totals</td>
                    {% for year, month, date in project_months %}
                    <td style="padding: 10px; border: 1px solid #ddd; text-align: center;">
                        <span class="month-total" data-year="{{ year }}" data-month="{{ month }}">0</span>
                    </td>
                    {% endfor %}
                    <td style="padding: 10px; border: 1px solid #ddd; text-align: center;">
                        <span id="grand-total">0</span>
                    </td>
                </tr>
            </tfoot>
        </table>
    </div>
    
    <div class="allocation-actions" style="margin-top: 20px;">
        <button type="button" class="button" onclick="distributeEvenly()">
            Distribute Hours Evenly
        </button>
        <button type="button" class="button" onclick="clearAllocations()">
            Clear All
        </button>
        <button type="button" class="button default" onclick="saveAllocations()">
            Save Allocations
        </button>
    </div>
    {% else %}
    <p style="padding: 20px; background: #f9f9f9; border-radius: 4px;">
        Please set project start and end dates, then save the project to allocate team members.
    </p>
    {% endif %}
</div>

<style>
.allocation-table input[type="number"] {
    border: 1px solid #ddd;
    border-radius: 3px;
    padding: 4px;
}
.allocation-table input[type="number"]:focus {
    border-color: #79aec8;
    outline: none;
}
.allocation-table tr:hover {
    background-color: #f9f9f9;
}
</style>

<script>
// Load existing allocations
const existingAllocations = {{ existing_allocations|safe }};

document.addEventListener('DOMContentLoaded', function() {
    const inputs = document.querySelectorAll('.allocation-input');
    const totalHours = {{ project.total_hours|default:0 }};
    
    // Load existing values
    Object.keys(existingAllocations).forEach(key => {
        const [memberId, year, month] = key.split('_');
        const input = document.querySelector(
            `.allocation-input[data-member="${memberId}"][data-year="${year}"][data-month="${month}"]`
        );
        if (input) {
            input.value = existingAllocations[key].hours;
        }
    });
    
    // Update totals when inputs change
    inputs.forEach(input => {
        input.addEventListener('input', updateTotals);
    });
    
    // Initial calculation
    updateTotals();
    
    function updateTotals() {
        let grandTotal = 0;
        const memberTotals = {};
        const monthTotals = {};
        
        inputs.forEach(input => {
            const value = parseFloat(input.value) || 0;
            const memberId = input.dataset.member;
            const year = input.dataset.year;
            const month = input.dataset.month;
            const key = `${year}_${month}`;
            
            memberTotals[memberId] = (memberTotals[memberId] || 0) + value;
            monthTotals[key] = (monthTotals[key] || 0) + value;
            grandTotal += value;
        });
        
        // Display member totals
        Object.keys(memberTotals).forEach(memberId => {
            const element = document.querySelector(`.member-total[data-member="${memberId}"]`);
            if (element) {
                element.textContent = memberTotals[memberId].toFixed(1);
            }
        });
        
        // Display month totals
        Object.keys(monthTotals).forEach(key => {
            const [year, month] = key.split('_');
            const element = document.querySelector(`.month-total[data-year="${year}"][data-month="${month}"]`);
            if (element) {
                element.textContent = monthTotals[key].toFixed(1);
            }
        });
        
        // Display grand total
        document.getElementById('grand-total').textContent = grandTotal.toFixed(1);
        document.getElementById('total-allocated').textContent = grandTotal.toFixed(1);
        
        // Update remaining hours
        if (totalHours > 0) {
            const remaining = totalHours - grandTotal;
            const remainingElement = document.getElementById('remaining-hours');
            remainingElement.textContent = remaining.toFixed(1);
            remainingElement.style.color = remaining < 0 ? '#dc2626' : '#059669';
        }
    }
    
    // Distribute hours evenly
    window.distributeEvenly = function() {
        if (totalHours > 0) {
            const numInputs = inputs.length;
            const hoursPerCell = (totalHours / numInputs).toFixed(1);
            
            inputs.forEach(input => {
                input.value = hoursPerCell;
            });
            
            updateTotals();
        }
    };
    
    // Clear all allocations
    window.clearAllocations = function() {
        if (confirm('Clear all allocations?')) {
            inputs.forEach(input => {
                input.value = 0;
            });
            updateTotals();
        }
    };
    
    // Save allocations
    window.saveAllocations = function() {
        const allocations = [];
        
        inputs.forEach(input => {
            const value = parseFloat(input.value) || 0;
            if (value > 0) {
                allocations.push({
                    user_profile: input.dataset.member,
                    year: input.dataset.year,
                    month: input.dataset.month,
                    hours: value
                });
            }
        });
        
        // Get CSRF token
        const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]').value;
        
        // Send to server
        fetch(`/admin/agency/project/{{ project.id }}/save-allocations/`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRFToken': csrfToken
            },
            body: JSON.stringify({ allocations: allocations })
        })
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success') {
                alert('Allocations saved successfully!');
                // Reload the page to show updated data
                window.location.reload();
            } else {
                alert('Error saving allocations: ' + (data.message || 'Unknown error'));
            }
        })
        .catch(error => {
            alert('Error saving allocations: ' + error);
        });
    };
});
</script>
EOF

print_status "Allocation template created!"

# Step 4: Test the setup
print_status "Testing admin setup..."
python manage.py check

# Step 5: Summary
echo ""
echo "========================================="
echo "Complete Admin Created!"
echo "========================================="
echo ""
print_status "What was created:"
echo "  ✓ Complete admin.py with all models"
echo "  ✓ Smart allocation grid for projects"
echo "  ✓ Permission controls (superuser-only for payroll)"
echo "  ✓ AJAX save functionality for allocations"
echo "  ✓ Dynamic month columns based on project dates"
echo ""
print_status "Features:"
echo "  - Grid shows only months within project timeline"
echo "  - Real-time calculation of totals"
echo "  - Save allocations without page reload"
echo "  - Distribute hours evenly across team/months"
echo "  - Shows remaining hours to allocate"
echo ""
print_status "To use:"
echo "  1. Edit any project in admin"
echo "  2. Set start and end dates"
echo "  3. Save the project"
echo "  4. The allocation grid will appear below"
echo "  5. Enter hours for each team member/month"
echo "  6. Click 'Save Allocations'"
echo ""

# Ask if user wants to test
read -p "Would you like to start the server and test? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    echo "Visit: http://127.0.0.1:8000/admin/agency/project/"
    python manage.py runserver
fi