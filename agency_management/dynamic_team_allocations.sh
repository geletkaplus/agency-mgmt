#!/bin/bash

# Dynamic Team Allocations Script
# This script creates a system where PMs first assign team members, then allocate hours

echo "========================================="
echo "Dynamic Team Assignment & Allocations"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_action() {
    echo -e "${BLUE}[ACTION]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    echo "Error: manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

# Step 1: Create migration for team assignments
print_status "Creating migration for project team assignments..."

cat > agency/migrations/0008_project_team_members.py << 'EOF'
from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [
        ('agency', '0007_auto_allocation_improvements'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='team_members',
            field=models.ManyToManyField(
                to='agency.UserProfile',
                related_name='assigned_projects',
                blank=True,
                help_text='Team members assigned to this project'
            ),
        ),
    ]
EOF

print_status "Migration created!"

# Step 2: Apply the migration
print_action "Applying migration..."
python manage.py migrate agency

# Step 3: Update models.py to add team_members field
print_status "Creating models patch for team_members field..."

cat > /tmp/models_team_members.patch << 'EOF'
# Add this to your Project model in models.py:

    team_members = models.ManyToManyField(
        'UserProfile',
        related_name='assigned_projects',
        blank=True,
        help_text='Team members assigned to this project'
    )
    
    @property
    def assigned_hours(self):
        """Total hours assigned to team members"""
        return self.allocations.aggregate(
            total=models.Sum('allocated_hours')
        )['total'] or Decimal('0')
EOF

# Step 4: Create the new admin.py with team assignment
print_status "Creating updated admin.py with team assignment..."

cat > agency/admin.py << 'EOF'
# agency/admin.py - With dynamic team assignment and allocations
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


# Company Admin
@admin.register(Company)
class CompanyAdmin(admin.ModelAdmin):
    list_display = ['name', 'code', 'created_at']
    search_fields = ['name', 'code']


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


# Client Admin
@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ['name', 'company', 'status', 'account_manager']
    list_filter = ['status', 'company']
    search_fields = ['name']


# Team Assignment Inline
class TeamAssignmentInline(admin.TabularInline):
    model = Project.team_members.through
    extra = 3
    verbose_name = "Team Member"
    verbose_name_plural = "Team Members"
    
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "userprofile":
            # Filter to show only active team members from the same company
            if hasattr(request, '_obj_') and request._obj_:
                kwargs["queryset"] = UserProfile.objects.filter(
                    company=request._obj_.company,
                    status__in=['full_time', 'part_time', 'contractor']
                ).select_related('user').order_by('user__last_name')
        return super().formfield_for_foreignkey(db_field, request, **kwargs)


# Dynamic Allocation Inline
class DynamicAllocationInline(admin.StackedInline):
    model = ProjectAllocation
    template = 'admin/agency/project/allocation_grid.html'
    extra = 0
    can_delete = False
    
    def has_add_permission(self, request, obj=None):
        return False


# Project Admin
@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'start_date', 'end_date', 
                    'total_revenue_display', 'team_size', 'allocation_status']
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    filter_horizontal = ['team_members']  # Nice widget for many-to-many
    
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
        ('Team Assignment', {
            'fields': ('project_manager', 'team_members'),
            'description': 'Select team members to assign to this project. Save the project after making changes to see the allocation grid.'
        })
    )
    
    # Only show allocation inline if project has dates and team
    def get_inline_instances(self, request, obj=None):
        inline_instances = []
        if obj and obj.start_date and obj.end_date and obj.team_members.exists():
            inline_instances.append(DynamicAllocationInline(self.model, self.admin_site))
        return inline_instances
    
    def total_revenue_display(self, obj):
        return f"${int(obj.total_revenue):,}"
    total_revenue_display.short_description = "Revenue"
    
    def team_size(self, obj):
        count = obj.team_members.count()
        return f"{count} member{'s' if count != 1 else ''}"
    team_size.short_description = "Team"
    
    def allocation_status(self, obj):
        if not obj.total_hours or not obj.team_members.exists():
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
    
    def get_form(self, request, obj=None, **kwargs):
        request._obj_ = obj
        form = super().get_form(request, obj, **kwargs)
        
        # Customize team_members field queryset
        if 'team_members' in form.base_fields:
            if obj:
                form.base_fields['team_members'].queryset = UserProfile.objects.filter(
                    company=obj.company,
                    status__in=['full_time', 'part_time', 'contractor']
                ).select_related('user').order_by('user__last_name')
            else:
                form.base_fields['team_members'].queryset = UserProfile.objects.none()
        
        return form
    
    def change_view(self, request, object_id, form_url='', extra_context=None):
        extra_context = extra_context or {}
        obj = self.get_object(request, object_id)
        
        if obj and obj.start_date and obj.end_date and obj.team_members.exists():
            # Calculate project months
            from datetime import date
            from dateutil.relativedelta import relativedelta
            
            project_months = []
            current = obj.start_date.replace(day=1)
            end = obj.end_date.replace(day=1)
            
            while current <= end:
                project_months.append((current.year, current.month, current))
                current += relativedelta(months=1)
            
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
                'assigned_team': obj.team_members.all().select_related('user'),
                'existing_allocations': json.dumps(allocation_dict),
                'show_allocation_grid': True
            })
        else:
            extra_context['show_allocation_grid'] = False
            if obj:
                if not obj.start_date or not obj.end_date:
                    messages.info(request, "Set project dates to enable hour allocation.")
                elif not obj.team_members.exists():
                    messages.info(request, "Assign team members to enable hour allocation.")
        
        return super().change_view(request, object_id, form_url, extra_context=extra_context)
    
    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        if change and 'start_date' in form.changed_data or 'end_date' in form.changed_data:
            messages.info(request, "Project dates changed. Please review team allocations below.")
    
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
                
                # Clear existing allocations first
                ProjectAllocation.objects.filter(project=project).delete()
                
                # Create new allocations
                for alloc_data in allocations:
                    if float(alloc_data['hours']) > 0:
                        user_profile = UserProfile.objects.get(id=alloc_data['user_profile'])
                        ProjectAllocation.objects.create(
                            project=project,
                            user_profile=user_profile,
                            year=int(alloc_data['year']),
                            month=int(alloc_data['month']),
                            allocated_hours=Decimal(str(alloc_data['hours'])),
                            hourly_rate=user_profile.hourly_rate
                        )
                
                return JsonResponse({'status': 'success'})
            except Exception as e:
                return JsonResponse({'status': 'error', 'message': str(e)})
        
        return JsonResponse({'status': 'error', 'message': 'Invalid request'})


# Project Allocation Admin
@admin.register(ProjectAllocation)
class ProjectAllocationAdmin(admin.ModelAdmin):
    list_display = ['project', 'user_profile', 'month_year', 'allocated_hours']
    list_filter = ['year', 'month', 'project__company']
    search_fields = ['project__name', 'user_profile__user__first_name']
    
    def month_year(self, obj):
        import calendar
        return f"{calendar.month_abbr[obj.month]} {obj.year}"


# Other admin classes remain the same...
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


# Register optional models
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

# Step 5: Create the allocation grid template
print_status "Creating allocation grid template..."

mkdir -p templates/admin/agency/project
cat > templates/admin/agency/project/allocation_grid.html << 'EOF'
{% load i18n admin_urls static %}

{% if show_allocation_grid %}
<div class="module" id="allocation-grid">
    <h2>Hour Allocations</h2>
    
    <div class="allocation-info" style="margin: 10px 0; padding: 10px; background: #f0f0f0; border-radius: 4px;">
        <p style="margin: 5px 0;">
            <strong>Project Duration:</strong> 
            {{ project.start_date|date:"M d, Y" }} - {{ project.end_date|date:"M d, Y" }}
            ({{ project_months|length }} month{{ project_months|length|pluralize }})
        </p>
        <p style="margin: 5px 0;">
            <strong>Assigned Team:</strong> {{ assigned_team|length }} member{{ assigned_team|length|pluralize }}
        </p>
        {% if project.total_hours %}
        <p style="margin: 5px 0;">
            <strong>Budget:</strong> {{ project.total_hours|floatformat:0 }} hours
            | <strong>Allocated:</strong> <span id="total-allocated">0</span> hours
            | <strong>Remaining:</strong> <span id="remaining-hours">{{ project.total_hours|floatformat:0 }}</span> hours
        </p>
        {% endif %}
    </div>
    
    {% if assigned_team %}
    <div class="allocation-grid" style="overflow-x: auto; margin-bottom: 20px;">
        <table class="allocation-table" style="width: 100%; border-collapse: collapse;">
            <thead>
                <tr style="background: #79aec8;">
                    <th style="padding: 10px; text-align: left; color: white; position: sticky; left: 0; background: #79aec8; z-index: 10; min-width: 250px;">
                        Team Member
                    </th>
                    {% for year, month, date in project_months %}
                    <th style="padding: 10px; text-align: center; color: white; min-width: 100px;">
                        {{ date|date:"M" }}<br>{{ year }}
                    </th>
                    {% endfor %}
                    <th style="padding: 10px; text-align: center; color: white; min-width: 100px;">
                        Total
                    </th>
                </tr>
            </thead>
            <tbody>
                {% for member in assigned_team %}
                <tr class="allocation-row" data-member-id="{{ member.id }}">
                    <td style="padding: 10px; border: 1px solid #ddd; position: sticky; left: 0; background: white; z-index: 5;">
                        <strong>{{ member.user.get_full_name|default:member.user.username }}</strong><br>
                        <small style="color: #666;">
                            {{ member.get_role_display }} 
                            {% if request.user.is_superuser %}
                            • ${{ member.hourly_rate|floatformat:0 }}/hr
                            {% endif %}
                        </small>
                    </td>
                    {% for year, month, date in project_months %}
                    <td style="padding: 5px; border: 1px solid #ddd; text-align: center;">
                        <input type="number" 
                               class="allocation-input"
                               data-member="{{ member.id }}"
                               data-year="{{ year }}"
                               data-month="{{ month }}"
                               value="0"
                               min="0"
                               step="1"
                               style="width: 80px; text-align: center; padding: 4px;">
                    </td>
                    {% endfor %}
                    <td style="padding: 10px; border: 1px solid #ddd; text-align: center; font-weight: bold; background: #f9f9f9;">
                        <span class="member-total" data-member="{{ member.id }}">0</span>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
            <tfoot>
                <tr style="background: #f5f5f5; font-weight: bold;">
                    <td style="padding: 10px; border: 1px solid #ddd; position: sticky; left: 0; background: #f5f5f5;">
                        Monthly Totals
                    </td>
                    {% for year, month, date in project_months %}
                    <td style="padding: 10px; border: 1px solid #ddd; text-align: center;">
                        <span class="month-total" data-year="{{ year }}" data-month="{{ month }}">0</span>
                    </td>
                    {% endfor %}
                    <td style="padding: 10px; border: 1px solid #ddd; text-align: center; background: #e5e7eb;">
                        <span id="grand-total">0</span>
                    </td>
                </tr>
            </tfoot>
        </table>
    </div>
    
    <div class="allocation-actions" style="margin-top: 20px;">
        {% if project.total_hours %}
        <button type="button" class="button" onclick="distributeEvenly()" style="margin-right: 10px;">
            <i class="fas fa-equals"></i> Distribute {{ project.total_hours|floatformat:0 }} Hours Evenly
        </button>
        {% endif %}
        <button type="button" class="button" onclick="clearAllocations()" style="margin-right: 10px;">
            <i class="fas fa-eraser"></i> Clear All
        </button>
        <button type="button" class="button default" onclick="saveAllocations()">
            <i class="fas fa-save"></i> Save Allocations
        </button>
        <span id="save-status" style="margin-left: 10px; color: green; display: none;">
            <i class="fas fa-check"></i> Saved!
        </span>
    </div>
    {% else %}
    <p style="padding: 20px; background: #fff3cd; border: 1px solid #ffeeba; border-radius: 4px; color: #856404;">
        <strong>No team members assigned yet.</strong><br>
        Use the "Team Members" field above to assign people to this project, then save to see the allocation grid.
    </p>
    {% endif %}
</div>

<style>
.allocation-table input[type="number"] {
    border: 1px solid #ddd;
    border-radius: 3px;
}
.allocation-table input[type="number"]:focus {
    border-color: #79aec8;
    outline: none;
    box-shadow: 0 0 0 2px rgba(121, 174, 200, 0.2);
}
.allocation-table tr:hover {
    background-color: #f9f9f9;
}
.allocation-actions button {
    cursor: pointer;
}
.allocation-actions button:hover {
    opacity: 0.8;
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
            // Round to nearest whole number on blur
            this.value = Math.round(parseFloat(this.value) || 0);
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
        
        // Update member totals
        Object.keys(memberTotals).forEach(memberId => {
            const element = document.querySelector(`.member-total[data-member="${memberId}"]`);
            if (element) {
                element.textContent = memberTotals[memberId];
            }
        });
        
        // Update month totals
        Object.keys(monthTotals).forEach(key => {
            const [year, month] = key.split('_');
            const element = document.querySelector(`.month-total[data-year="${year}"][data-month="${month}"]`);
            if (element) {
                element.textContent = monthTotals[key];
            }
        });
        
        // Update grand total
        document.getElementById('grand-total').textContent = grandTotal;
        document.getElementById('total-allocated').textContent = grandTotal;
        
        // Update remaining hours
        if (totalBudget > 0) {
            const remaining = totalBudget - grandTotal;
            const remainingElement = document.getElementById('remaining-hours');
            remainingElement.textContent = remaining;
            remainingElement.style.color = remaining < 0 ? '#dc2626' : (remaining === 0 ? '#059669' : '#000');
        }
    }
    
    // Distribute hours evenly
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
    
    // Clear all allocations
    window.clearAllocations = function() {
        if (confirm('Clear all allocations? This cannot be undone.')) {
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
            allocations.push({
                user_profile: input.dataset.member,
                year: input.dataset.year,
                month: input.dataset.month,
                hours: value
            });
        });
        
        // Get CSRF token
        const csrfToken = document.querySelector('[name=csrfmiddlewaretoken]').value;
        
        // Show saving status
        const statusElement = document.getElementById('save-status');
        statusElement.style.display = 'none';
        
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
                statusElement.style.display = 'inline';
                setTimeout(() => {
                    statusElement.style.display = 'none';
                }, 3000);
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
{% endif %}
EOF

# Step 6: Summary
echo ""
echo "========================================="
echo "Dynamic Team Allocations Complete!"
echo "========================================="
echo ""
print_status "What was added:"
echo "  ✓ team_members field on Project model"
echo "  ✓ PM can select which team members to assign"
echo "  ✓ Allocation grid only shows assigned team members"
echo "  ✓ Grid updates when project dates change"
echo "  ✓ Clear feedback when setup is incomplete"
echo ""
print_action "Workflow:"
echo "  1. Create/edit a project"
echo "  2. Set start and end dates"
echo "  3. Select team members in the 'Team Members' field"
echo "  4. Save the project"
echo "  5. Allocation grid appears with only assigned members"
echo "  6. Enter hours for each person/month"
echo "  7. Click 'Save Allocations'"
echo ""
print_status "Features:"
echo "  - Uses Django's filter_horizontal widget for easy team selection"
echo "  - Grid dynamically adjusts to date changes"
echo "  - Shows helpful messages when setup incomplete"
echo "  - Distribute hours evenly based on budget"
echo "  - Real-time feedback on allocation status"
echo ""

# Ask to apply models patch
read -p "Would you like to see the models.py patch for team_members? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cat /tmp/models_team_members.patch
fi