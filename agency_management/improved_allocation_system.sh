#!/bin/bash

# Improved Allocation System Script
# This creates a better team assignment UI and dynamic allocation grid

echo "========================================="
echo "Improved Team Assignment & Allocation"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    echo "Error: manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Create improved admin.py
print_status "Creating improved admin.py with better team assignment..."

cat > agency/admin.py << 'EOF'
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
EOF

# Step 2: Create the improved allocation grid template
print_status "Creating improved allocation grid template..."

mkdir -p templates/admin/agency/project
cat > templates/admin/agency/project/allocation_grid.html << 'EOF'
{% load i18n admin_urls static %}

{% if show_allocation_grid %}
<div class="module" id="allocation-grid-module">
    <h2>Hour Allocations</h2>
    
    <div class="allocation-info" style="margin: 10px 0; padding: 15px; background: #f8f9fa; border-radius: 4px; border: 1px solid #dee2e6;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
            <div>
                <p style="margin: 0 0 5px 0;">
                    <strong>Project Timeline:</strong> 
                    {{ project.start_date|date:"M d, Y" }} - {{ project.end_date|date:"M d, Y" }}
                    <span style="color: #6c757d;">({{ project_months|length }} month{{ project_months|length|pluralize }})</span>
                </p>
                {% if project.total_hours %}
                <p style="margin: 0;">
                    <strong>Budget:</strong> 
                    <span style="font-size: 1.1em;">{{ project.total_hours|floatformat:0 }}</span> hours
                    | <strong>Allocated:</strong> 
                    <span id="total-allocated" style="font-size: 1.1em;">0</span> hours
                    | <strong>Remaining:</strong> 
                    <span id="remaining-hours" style="font-size: 1.1em; font-weight: bold;">{{ project.total_hours|floatformat:0 }}</span> hours
                </p>
                {% endif %}
            </div>
            <div>
                <span style="color: #dc3545; font-size: 0.9em;">
                    <i class="fas fa-info-circle"></i> 
                    Save the project after changing dates to update this grid
                </span>
            </div>
        </div>
    </div>
    
    {% if team_members %}
    <div style="overflow-x: auto; margin-bottom: 20px; border: 1px solid #dee2e6; border-radius: 4px;">
        <table class="allocation-table" style="width: 100%; border-collapse: collapse; margin: 0;">
            <thead>
                <tr style="background: #495057;">
                    <th style="padding: 12px; text-align: left; color: white; position: sticky; left: 0; background: #495057; z-index: 10; min-width: 250px; border-right: 2px solid #6c757d;">
                        Team Member
                    </th>
                    {% for month_data in project_months %}
                    <th style="padding: 12px; text-align: center; color: white; min-width: 100px; border-right: 1px solid #6c757d;">
                        <div style="font-weight: bold;">{{ month_data.month_name }}</div>
                        <div style="font-size: 0.85em; opacity: 0.8;">{{ month_data.year }}</div>
                    </th>
                    {% endfor %}
                    <th style="padding: 12px; text-align: center; color: white; min-width: 100px; background: #343a40;">
                        Total
                    </th>
                </tr>
            </thead>
            <tbody>
                {% for member in team_members %}
                <tr class="allocation-row" data-member-id="{{ member.id }}">
                    <td style="padding: 10px; border-bottom: 1px solid #dee2e6; position: sticky; left: 0; background: white; z-index: 5; border-right: 2px solid #dee2e6;">
                        <div>
                            <strong>{{ member.user.get_full_name|default:member.user.username }}</strong>
                        </div>
                        <div style="font-size: 0.85em; color: #6c757d;">
                            {{ member.get_role_display }} 
                            {% if request.user.is_superuser %}
                            • ${{ member.hourly_rate|floatformat:0 }}/hr
                            {% endif %}
                        </div>
                    </td>
                    {% for month_data in project_months %}
                    <td style="padding: 5px; border-bottom: 1px solid #dee2e6; border-right: 1px solid #dee2e6; text-align: center;">
                        <input type="number" 
                               class="allocation-input"
                               data-member="{{ member.id }}"
                               data-year="{{ month_data.year }}"
                               data-month="{{ month_data.month }}"
                               value="0"
                               min="0"
                               step="1"
                               style="width: 70px; text-align: center; padding: 6px; border: 1px solid #ced4da; border-radius: 3px;">
                    </td>
                    {% endfor %}
                    <td style="padding: 10px; border-bottom: 1px solid #dee2e6; text-align: center; font-weight: bold; background: #f8f9fa;">
                        <span class="member-total" data-member="{{ member.id }}">0</span>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
            <tfoot>
                <tr style="background: #e9ecef; font-weight: bold;">
                    <td style="padding: 10px; border-right: 2px solid #dee2e6; position: sticky; left: 0; background: #e9ecef;">
                        Monthly Totals
                    </td>
                    {% for month_data in project_months %}
                    <td style="padding: 10px; border-right: 1px solid #dee2e6; text-align: center;">
                        <span class="month-total" data-year="{{ month_data.year }}" data-month="{{ month_data.month }}">0</span>
                    </td>
                    {% endfor %}
                    <td style="padding: 10px; text-align: center; background: #495057; color: white;">
                        <span id="grand-total">0</span>
                    </td>
                </tr>
            </tfoot>
        </table>
    </div>
    
    <div class="allocation-actions" style="margin-top: 20px; padding: 15px; background: #f8f9fa; border-radius: 4px;">
        {% if project.total_hours %}
        <button type="button" class="button" onclick="distributeEvenly()" style="margin-right: 10px;">
            Distribute {{ project.total_hours|floatformat:0 }} Hours Evenly
        </button>
        {% endif %}
        <button type="button" class="button" onclick="clearAllocations()" style="margin-right: 10px;">
            Clear All
        </button>
        <button type="button" class="button default" onclick="saveAllocations()" style="background: #28a745; color: white; border-color: #28a745;">
            Save Allocations
        </button>
        <span id="save-status" style="margin-left: 15px; color: #28a745; display: none; font-weight: bold;">
            ✓ Saved successfully!
        </span>
    </div>
    {% else %}
    <p style="padding: 20px; background: #fff3cd; border: 1px solid #ffeeba; border-radius: 4px; color: #856404;">
        <strong>No team members found.</strong><br>
        Add team members using the "Team Members" section above, then save the project to see the allocation grid.
    </p>
    {% endif %}
</div>

<style>
#allocation-grid-module {
    margin-top: 30px;
}

.allocation-table input[type="number"] {
    transition: all 0.2s ease;
}

.allocation-table input[type="number"]:focus {
    border-color: #80bdff !important;
    outline: 0;
    box-shadow: 0 0 0 0.2rem rgba(0,123,255,.25);
}

.allocation-table input[type="number"]:hover {
    border-color: #80bdff;
}

.allocation-table tr:hover {
    background-color: #f8f9fa;
}

.allocation-actions button {
    cursor: pointer;
    padding: 8px 16px;
    border-radius: 4px;
    border: 1px solid #ced4da;
    background: white;
    transition: all 0.2s ease;
}

.allocation-actions button:hover {
    background: #e9ecef;
}

.allocation-actions button.default:hover {
    background: #218838 !important;
}
</style>

<script>
// Load existing allocations
const existingAllocations = {{ existing_allocations|safe }};
const totalBudget = {{ project.total_hours|default:0 }};

document.addEventListener('DOMContentLoaded', function() {
    const inputs = document.querySelectorAll('.allocation-input');
    
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
    
    // Add event listeners
    inputs.forEach(input => {
        input.addEventListener('input', updateTotals);
        input.addEventListener('change', function() {
            this.value = Math.max(0, Math.round(parseFloat(this.value) || 0));
            updateTotals();
        });
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
        
        // Update displays
        Object.keys(memberTotals).forEach(memberId => {
            const element = document.querySelector(`.member-total[data-member="${memberId}"]`);
            if (element) element.textContent = memberTotals[memberId];
        });
        
        Object.keys(monthTotals).forEach(key => {
            const [year, month] = key.split('_');
            const element = document.querySelector(`.month-total[data-year="${year}"][data-month="${month}"]`);
            if (element) element.textContent = monthTotals[key];
        });
        
        document.getElementById('grand-total').textContent = grandTotal;
        document.getElementById('total-allocated').textContent = grandTotal;
        
        // Update remaining
        if (totalBudget > 0) {
            const remaining = totalBudget - grandTotal;
            const remainingElement = document.getElementById('remaining-hours');
            remainingElement.textContent = remaining;
            remainingElement.style.color = remaining < 0 ? '#dc3545' : (remaining === 0 ? '#28a745' : '#212529');
        }
    }
    
    window.distributeEvenly = function() {
        if (totalBudget > 0 && inputs.length > 0) {
            const hoursPerCell = Math.floor(totalBudget / inputs.length);
            const remainder = totalBudget % inputs.length;
            
            inputs.forEach((input, index) => {
                input.value = hoursPerCell + (index < remainder ? 1 : 0);
            });
            
            updateTotals();
        }
    };
    
    window.clearAllocations = function() {
        if (confirm('Clear all allocations?')) {
            inputs.forEach(input => input.value = 0);
            updateTotals();
        }
    };
    
    window.saveAllocations = function() {
        const allocations = [];
        
        inputs.forEach(input => {
            const value = parseFloat(input.value) || 0;
            allocations.push({
                user_profile: input.dataset.member,
                year: input.dataset.year,
                month: input.dataset.month,
                hours: value
            });
        });
        
        const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]').value;
        const statusElement = document.getElementById('save-status');
        statusElement.style.display = 'none';
        
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
                statusElement.style.display = 'inline';
                setTimeout(() => {
                    statusElement.style.display = 'none';
                }, 3000);
            } else {
                alert('Error: ' + (data.message || 'Unknown error'));
            }
        })
        .catch(error => {
            alert('Error saving: ' + error);
        });
    };
});
</script>
{% else %}
<div class="module" style="margin-top: 30px;">
    <h2>Hour Allocations</h2>
    <p style="padding: 20px; background: #d1ecf1; border: 1px solid #bee5eb; border-radius: 4px; color: #0c5460;">
        <strong>Not available yet.</strong><br>
        Please set both start and end dates for the project, then save to see the hour allocation grid.
    </p>
</div>
{% endif %}
EOF

# Step 3: Create CSS file for better styling
print_status "Creating CSS file..."

mkdir -p static/admin/css
cat > static/admin/css/project_admin.css << 'EOF'
/* Better styling for team assignment inline */
.inline-group .tabular tr.has_original td {
    padding-top: 8px !important;
}

.inline-group h2 {
    background: #495057 !important;
    color: white !important;
}

/* Highlight date change warning */
.messagelist .warning {
    background: #fff3cd !important;
    border: 1px solid #ffeeba !important;
    color: #856404 !important;
}
EOF

# Step 4: Summary
echo ""
echo "========================================="
echo "Improved Allocation System Complete!"
echo "========================================="
echo ""
print_status "Improvements made:"
echo "  ✓ Simple tabular inline for team assignment (with 5 empty rows)"
echo "  ✓ Clear month names above each column in the grid"
echo "  ✓ Warning message when dates change"
echo "  ✓ Grid shows ALL team members if none specifically assigned"
echo "  ✓ Better visual styling with proper borders and spacing"
echo "  ✓ Reminder to save after changing dates"
echo ""
print_status "How it works:"
echo "  1. Add team members using the simple inline (or leave empty for all)"
echo "  2. Set/change project dates"
echo "  3. Save the project"
echo "  4. Grid updates with new date range"
echo "  5. Allocate hours and save allocations"
echo ""

# Ask if user wants to collect static files
read -p "Would you like to collect static files? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Collecting static files..."
    python manage.py collectstatic --noinput
fi

# Ask if user wants to test
read -p "Would you like to start the server and test? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting development server..."
    echo "Visit: http://127.0.0.1:8000/admin/agency/project/"
    python manage.py runserver
fi