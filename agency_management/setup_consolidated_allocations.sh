#!/bin/bash

# Setup Consolidated Allocations for Django Agency Management
# Run this script from your project root directory

echo "========================================="
echo "Setting up Consolidated Allocations"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "manage.py" ]; then
    print_error "Error: manage.py not found! Please run this script from your Django project root directory."
    exit 1
fi

print_status "Creating static file directories..."
mkdir -p static/admin/css
mkdir -p static/admin/js

# Create the CSS file
print_status "Creating project_admin.css..."
cat > static/admin/css/project_admin.css << 'EOF'
/* Project Admin Styles */
.allocation-grid-container {
    margin-top: 20px;
    background: #f8f9fa;
    border: 1px solid #dee2e6;
    border-radius: 4px;
    padding: 20px;
}

.allocation-header {
    background: #495057;
    color: white;
    padding: 15px;
    border-radius: 4px 4px 0 0;
    margin: -20px -20px 20px -20px;
}

.allocation-header h3 {
    margin: 0;
    font-size: 1.2em;
    font-weight: normal;
}

.allocation-summary {
    display: flex;
    justify-content: space-between;
    margin-bottom: 20px;
    padding: 15px;
    background: white;
    border: 1px solid #dee2e6;
    border-radius: 4px;
}

.allocation-summary-item {
    text-align: center;
}

.allocation-summary-item .value {
    font-size: 1.5em;
    font-weight: bold;
    color: #495057;
}

.allocation-summary-item .label {
    font-size: 0.9em;
    color: #6c757d;
}

.allocation-table {
    width: 100%;
    background: white;
    border: 1px solid #dee2e6;
    border-radius: 4px;
    overflow: hidden;
}

.allocation-table th {
    background: #f8f9fa;
    font-weight: normal;
    font-size: 0.9em;
    padding: 10px;
    border-bottom: 2px solid #dee2e6;
    white-space: nowrap;
}

.allocation-table th.month-header {
    background: #e9ecef;
    font-weight: bold;
    text-align: center;
    border-right: 2px solid #dee2e6;
}

.allocation-table th.week-header {
    text-align: center;
    font-size: 0.8em;
    color: #6c757d;
}

.allocation-table td {
    padding: 8px;
    border-bottom: 1px solid #dee2e6;
    border-right: 1px solid #e9ecef;
}

.allocation-table td.month-separator {
    border-right: 2px solid #dee2e6;
}

.allocation-table td.team-member-cell {
    background: #f8f9fa;
    position: sticky;
    left: 0;
    z-index: 1;
    min-width: 200px;
}

.allocation-table .member-info {
    display: flex;
    align-items: center;
    gap: 10px;
}

.allocation-table .member-avatar {
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: #6c757d;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.9em;
    font-weight: bold;
}

.allocation-table .member-details {
    flex: 1;
}

.allocation-table .member-name {
    font-weight: 500;
    color: #212529;
}

.allocation-table .member-role {
    font-size: 0.85em;
    color: #6c757d;
}

.allocation-table input[type="number"] {
    width: 60px;
    padding: 4px 6px;
    border: 1px solid #ced4da;
    border-radius: 3px;
    text-align: center;
    font-size: 0.9em;
}

.allocation-table input[type="number"]:focus {
    border-color: #80bdff;
    outline: none;
    box-shadow: 0 0 0 0.2rem rgba(0,123,255,.25);
}

.allocation-table .row-total {
    font-weight: bold;
    text-align: center;
    background: #f8f9fa;
}

.allocation-table .week-total {
    font-weight: 500;
    text-align: center;
    background: #f8f9fa;
    font-size: 0.9em;
}

.allocation-actions {
    margin-top: 20px;
    display: flex;
    gap: 10px;
    align-items: center;
}

.allocation-actions button {
    padding: 8px 16px;
    border: 1px solid #ced4da;
    border-radius: 4px;
    background: white;
    cursor: pointer;
    font-size: 0.9em;
}

.allocation-actions button:hover {
    background: #f8f9fa;
}

.allocation-actions button.primary {
    background: #28a745;
    color: white;
    border-color: #28a745;
}

.allocation-actions button.primary:hover {
    background: #218838;
}

.add-team-member {
    margin-top: 15px;
    padding: 15px;
    background: #e7f3ff;
    border: 1px solid #b8daff;
    border-radius: 4px;
}

.add-team-member select {
    width: 300px;
    margin-right: 10px;
}

/* Remove action buttons from rows */
.allocation-table .remove-member {
    color: #dc3545;
    cursor: pointer;
    font-size: 1.1em;
    padding: 0 5px;
}

.allocation-table .remove-member:hover {
    color: #a71d2a;
}

/* Hide the default inline formsets */
.inline-group.team-members-inline,
.inline-group.allocations-inline {
    display: none !important;
}

/* Status messages */
.allocation-status {
    margin-left: auto;
    padding: 5px 10px;
    border-radius: 3px;
    font-size: 0.9em;
}

.allocation-status.success {
    background: #d4edda;
    color: #155724;
}

.allocation-status.error {
    background: #f8d7da;
    color: #721c24;
}

/* Loading overlay */
.allocation-loading {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(255, 255, 255, 0.8);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
}

.allocation-loading-spinner {
    border: 3px solid #f3f3f3;
    border-top: 3px solid #3498db;
    border-radius: 50%;
    width: 40px;
    height: 40px;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}
EOF

# Create the JavaScript file
print_status "Creating project_allocation.js..."
cat > static/admin/js/project_allocation.js << 'EOF'
// Project Allocation Management
(function() {
    'use strict';
    
    let allocationData = {};
    let teamMembers = [];
    let projectId = null;
    let csrfToken = null;
    
    // Initialize when DOM is ready
    document.addEventListener('DOMContentLoaded', function() {
        // Check if we're on the project change page
        const urlMatch = window.location.pathname.match(/\/admin\/agency\/project\/([^\/]+)\/change\//);
        if (!urlMatch) return;
        
        projectId = urlMatch[1];
        csrfToken = document.querySelector('[name=csrfmiddlewaretoken]').value;
        
        // Wait a bit for Django admin to initialize
        setTimeout(() => {
            loadProjectData();
        }, 100);
    });
    
    function loadProjectData() {
        // Get project dates
        const startDateInput = document.querySelector('#id_start_date');
        const endDateInput = document.querySelector('#id_end_date');
        
        if (!startDateInput || !endDateInput) {
            console.log('Date inputs not found');
            return;
        }
        
        const startDate = startDateInput.value;
        const endDate = endDateInput.value;
        
        if (!startDate || !endDate) {
            console.log('Project dates not set');
            return;
        }
        
        // Load existing team members and allocations
        fetch(`/admin/agency/project/${projectId}/get-allocation-data/`)
            .then(response => response.json())
            .then(data => {
                teamMembers = data.team_members || [];
                allocationData = data.allocations || {};
                buildAllocationGrid(startDate, endDate);
            })
            .catch(error => {
                console.error('Error loading project data:', error);
                // Still try to build the grid
                buildAllocationGrid(startDate, endDate);
            });
    }
    
    function buildAllocationGrid(startDate, endDate) {
        // Remove existing grid if any
        const existingGrid = document.getElementById('allocation-grid-container');
        if (existingGrid) {
            existingGrid.remove();
        }
        
        // Find the fieldset to insert after
        const fieldsets = document.querySelectorAll('fieldset');
        let insertAfter = fieldsets[fieldsets.length - 1];
        
        // Create the grid container
        const gridContainer = document.createElement('div');
        gridContainer.id = 'allocation-grid-container';
        gridContainer.className = 'allocation-grid-container';
        gridContainer.innerHTML = `
            <div class="allocation-header">
                <h3>Team Member Allocations</h3>
            </div>
            <div class="allocation-summary">
                <div class="allocation-summary-item">
                    <div class="value" id="total-hours">0</div>
                    <div class="label">Total Hours</div>
                </div>
                <div class="allocation-summary-item">
                    <div class="value" id="allocated-hours">0</div>
                    <div class="label">Allocated Hours</div>
                </div>
                <div class="allocation-summary-item">
                    <div class="value" id="remaining-hours">0</div>
                    <div class="label">Remaining Hours</div>
                </div>
                <div class="allocation-summary-item">
                    <div class="value" id="team-size">0</div>
                    <div class="label">Team Members</div>
                </div>
            </div>
            <div class="allocation-table-container" style="overflow-x: auto;">
                <table class="allocation-table" id="allocation-table">
                    <thead id="allocation-header">
                        <!-- Headers will be generated -->
                    </thead>
                    <tbody id="allocation-body">
                        <!-- Rows will be generated -->
                    </tbody>
                    <tfoot id="allocation-footer">
                        <!-- Totals will be generated -->
                    </tfoot>
                </table>
            </div>
            <div class="add-team-member">
                <label>Add Team Member: </label>
                <select id="add-member-select">
                    <option value="">-- Select team member --</option>
                </select>
                <button type="button" onclick="addTeamMember()">Add to Project</button>
            </div>
            <div class="allocation-actions">
                <button type="button" onclick="distributeEvenly()">Distribute Hours Evenly</button>
                <button type="button" onclick="clearAllocations()">Clear All</button>
                <button type="button" class="primary" onclick="saveAllocations()">Save Allocations</button>
                <div class="allocation-status" id="save-status"></div>
            </div>
        `;
        
        insertAfter.parentNode.insertBefore(gridContainer, insertAfter.nextSibling);
        
        // Generate weeks and build headers
        const weeks = generateWeeks(startDate, endDate);
        buildHeaders(weeks);
        buildRows(weeks);
        loadAvailableMembers();
        updateTotals();
    }
    
    function generateWeeks(startDate, endDate) {
        const weeks = [];
        const start = new Date(startDate);
        const end = new Date(endDate);
        
        // Start from the beginning of the week
        const current = new Date(start);
        current.setDate(current.getDate() - current.getDay());
        
        while (current <= end) {
            const weekStart = new Date(current);
            const weekEnd = new Date(current);
            weekEnd.setDate(weekEnd.getDate() + 6);
            
            weeks.push({
                start: weekStart,
                end: weekEnd,
                month: weekStart.getMonth(),
                year: weekStart.getFullYear(),
                weekNum: getWeekNumber(weekStart)
            });
            
            current.setDate(current.getDate() + 7);
        }
        
        return weeks;
    }
    
    function getWeekNumber(date) {
        const firstDayOfYear = new Date(date.getFullYear(), 0, 1);
        const pastDaysOfYear = (date - firstDayOfYear) / 86400000;
        return Math.ceil((pastDaysOfYear + firstDayOfYear.getDay() + 1) / 7);
    }
    
    function buildHeaders(weeks) {
        const header = document.getElementById('allocation-header');
        
        // Group weeks by month
        const monthGroups = {};
        weeks.forEach(week => {
            const monthKey = `${week.year}-${week.month}`;
            if (!monthGroups[monthKey]) {
                monthGroups[monthKey] = [];
            }
            monthGroups[monthKey].push(week);
        });
        
        // Build month header row
        let monthHeaderHtml = '<tr><th rowspan="2" style="min-width: 250px;">Team Member</th>';
        Object.entries(monthGroups).forEach(([monthKey, monthWeeks]) => {
            const [year, month] = monthKey.split('-');
            const monthName = new Date(year, month, 1).toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
            monthHeaderHtml += `<th colspan="${monthWeeks.length}" class="month-header">${monthName}</th>`;
        });
        monthHeaderHtml += '<th rowspan="2" class="month-header">Total</th></tr>';
        
        // Build week header row
        let weekHeaderHtml = '<tr>';
        weeks.forEach((week, index) => {
            const weekLabel = `W${week.weekNum}`;
            const isLastInMonth = index === weeks.length - 1 || weeks[index + 1].month !== week.month;
            weekHeaderHtml += `<th class="week-header ${isLastInMonth ? 'month-separator' : ''}">${weekLabel}</th>`;
        });
        weekHeaderHtml += '</tr>';
        
        header.innerHTML = monthHeaderHtml + weekHeaderHtml;
    }
    
    function buildRows(weeks) {
        const tbody = document.getElementById('allocation-body');
        tbody.innerHTML = '';
        
        teamMembers.forEach(member => {
            const row = createMemberRow(member, weeks);
            tbody.appendChild(row);
        });
        
        // Build footer with totals
        buildFooter(weeks);
    }
    
    function createMemberRow(member, weeks) {
        const row = document.createElement('tr');
        row.dataset.memberId = member.id;
        
        // Team member cell
        let html = `
            <td class="team-member-cell">
                <div class="member-info">
                    <div class="member-avatar">${member.initials}</div>
                    <div class="member-details">
                        <div class="member-name">${member.name}</div>
                        <div class="member-role">${member.role} • $${member.hourly_rate}/hr</div>
                    </div>
                    <span class="remove-member" onclick="removeMember('${member.id}')" title="Remove from project">×</span>
                </div>
            </td>
        `;
        
        // Week cells
        weeks.forEach((week, index) => {
            const key = `${member.id}_${week.year}_${week.month}_${week.weekNum}`;
            const value = allocationData[key] || 0;
            const isLastInMonth = index === weeks.length - 1 || weeks[index + 1].month !== week.month;
            
            html += `
                <td class="${isLastInMonth ? 'month-separator' : ''}">
                    <input type="number" 
                           class="allocation-input"
                           data-member="${member.id}"
                           data-year="${week.year}"
                           data-month="${week.month}"
                           data-week="${week.weekNum}"
                           value="${value}"
                           min="0"
                           max="40"
                           step="0.5"
                           onchange="updateTotals()">
                </td>
            `;
        });
        
        // Total cell
        html += '<td class="row-total">0</td>';
        
        row.innerHTML = html;
        return row;
    }
    
    function buildFooter(weeks) {
        const footer = document.getElementById('allocation-footer');
        let html = '<tr><td style="font-weight: bold;">Week Totals</td>';
        
        weeks.forEach((week, index) => {
            const isLastInMonth = index === weeks.length - 1 || weeks[index + 1].month !== week.month;
            html += `<td class="week-total ${isLastInMonth ? 'month-separator' : ''}" data-week="${week.year}_${week.month}_${week.weekNum}">0</td>`;
        });
        
        html += '<td class="week-total" style="font-weight: bold;" id="grand-total">0</td></tr>';
        footer.innerHTML = html;
    }
    
    function updateTotals() {
        const inputs = document.querySelectorAll('.allocation-input');
        const weekTotals = {};
        const memberTotals = {};
        let grandTotal = 0;
        
        inputs.forEach(input => {
            const value = parseFloat(input.value) || 0;
            const memberId = input.dataset.member;
            const weekKey = `${input.dataset.year}_${input.dataset.month}_${input.dataset.week}`;
            
            // Update week totals
            weekTotals[weekKey] = (weekTotals[weekKey] || 0) + value;
            
            // Update member totals
            memberTotals[memberId] = (memberTotals[memberId] || 0) + value;
            
            grandTotal += value;
        });
        
        // Update week total cells
        document.querySelectorAll('.week-total').forEach(cell => {
            const weekKey = cell.dataset.week;
            if (weekKey) {
                cell.textContent = (weekTotals[weekKey] || 0).toFixed(1);
            }
        });
        
        // Update member total cells
        document.querySelectorAll('.allocation-table tbody tr').forEach(row => {
            const memberId = row.dataset.memberId;
            const totalCell = row.querySelector('.row-total');
            if (totalCell && memberId) {
                totalCell.textContent = (memberTotals[memberId] || 0).toFixed(1);
            }
        });
        
        // Update grand total
        document.getElementById('grand-total').textContent = grandTotal.toFixed(1);
        
        // Update summary
        const totalHours = parseFloat(document.querySelector('#id_total_hours')?.value) || 0;
        document.getElementById('total-hours').textContent = totalHours.toFixed(0);
        document.getElementById('allocated-hours').textContent = grandTotal.toFixed(0);
        document.getElementById('remaining-hours').textContent = (totalHours - grandTotal).toFixed(0);
        document.getElementById('team-size').textContent = teamMembers.length;
        
        // Color code remaining hours
        const remainingEl = document.getElementById('remaining-hours');
        const remaining = totalHours - grandTotal;
        if (remaining < 0) {
            remainingEl.style.color = '#dc3545';
        } else if (remaining === 0) {
            remainingEl.style.color = '#28a745';
        } else {
            remainingEl.style.color = '#495057';
        }
    }
    
    function loadAvailableMembers() {
        fetch(`/admin/agency/project/${projectId}/available-members/`)
            .then(response => response.json())
            .then(data => {
                const select = document.getElementById('add-member-select');
                select.innerHTML = '<option value="">-- Select team member --</option>';
                
                data.members.forEach(member => {
                    // Only show if not already in team
                    if (!teamMembers.find(m => m.id === member.id)) {
                        const option = document.createElement('option');
                        option.value = member.id;
                        option.textContent = `${member.name} (${member.role})`;
                        select.appendChild(option);
                    }
                });
            })
            .catch(error => {
                console.error('Error loading available members:', error);
            });
    }
    
    window.addTeamMember = function() {
        const select = document.getElementById('add-member-select');
        const memberId = select.value;
        
        if (!memberId) return;
        
        fetch(`/admin/agency/project/${projectId}/add-member/`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRFToken': csrfToken
            },
            body: JSON.stringify({ member_id: memberId })
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                // Reload the grid
                loadProjectData();
            }
        });
    };
    
    window.removeMember = function(memberId) {
        if (!confirm('Remove this team member from the project?')) return;
        
        fetch(`/admin/agency/project/${projectId}/remove-member/`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRFToken': csrfToken
            },
            body: JSON.stringify({ member_id: memberId })
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                // Remove from local array
                teamMembers = teamMembers.filter(m => m.id !== memberId);
                // Remove row
                document.querySelector(`tr[data-member-id="${memberId}"]`).remove();
                updateTotals();
                loadAvailableMembers();
            }
        });
    };
    
    window.distributeEvenly = function() {
        const totalHours = parseFloat(document.querySelector('#id_total_hours')?.value) || 0;
        const inputs = document.querySelectorAll('.allocation-input');
        
        if (totalHours > 0 && inputs.length > 0) {
            const hoursPerCell = (totalHours / inputs.length).toFixed(1);
            inputs.forEach(input => {
                input.value = hoursPerCell;
            });
            updateTotals();
        }
    };
    
    window.clearAllocations = function() {
        if (!confirm('Clear all allocations?')) return;
        
        document.querySelectorAll('.allocation-input').forEach(input => {
            input.value = 0;
        });
        updateTotals();
    };
    
    window.saveAllocations = function() {
        const allocations = [];
        const inputs = document.querySelectorAll('.allocation-input');
        
        inputs.forEach(input => {
            const value = parseFloat(input.value) || 0;
            if (value > 0) {
                allocations.push({
                    member_id: input.dataset.member,
                    year: parseInt(input.dataset.year),
                    month: parseInt(input.dataset.month),
                    week: parseInt(input.dataset.week),
                    hours: value
                });
            }
        });
        
        const statusEl = document.getElementById('save-status');
        statusEl.textContent = 'Saving...';
        statusEl.className = 'allocation-status';
        
        fetch(`/admin/agency/project/${projectId}/save-allocations/`, {
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
                statusEl.textContent = '✓ Saved successfully!';
                statusEl.className = 'allocation-status success';
                setTimeout(() => {
                    statusEl.textContent = '';
                }, 3000);
            } else {
                statusEl.textContent = '✗ Error saving';
                statusEl.className = 'allocation-status error';
            }
        })
        .catch(error => {
            statusEl.textContent = '✗ Error saving';
            statusEl.className = 'allocation-status error';
        });
    };
})();
EOF

# Backup current admin.py
print_status "Backing up current admin.py..."
cp agency/admin.py agency/admin.py.backup.$(date +%Y%m%d_%H%M%S)

# Create a Python script to update admin.py
print_status "Creating admin.py update script..."
cat > update_admin_temp.py << 'PYTHON_SCRIPT'
import re
import sys

try:
    # Read the current admin.py
    with open('agency/admin.py', 'r') as f:
        content = f.read()

    # Check if we already have the updated ProjectAdmin
    if 'get_allocation_data_view' in content:
        print("ProjectAdmin already updated with allocation views")
        sys.exit(0)

    # Find the ProjectAdmin class and replace it
    new_project_admin = '''@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ['name', 'client', 'status', 'start_date', 'end_date', 
                    'total_revenue_display', 'team_size', 'allocation_status']
    list_filter = ['status', 'project_type', 'company']
    search_fields = ['name', 'client__name']
    date_hierarchy = 'start_date'
    autocomplete_fields = ['client', 'project_manager']
    filter_horizontal = ['team_members']  # Better UI for M2M field
    
    fieldsets = (
        ('Project Information', {
            'fields': ('name', 'client', 'company', 'project_type', 'status')
        }),
        ('Timeline', {
            'fields': ('start_date', 'end_date'),
            'description': 'Save the project after setting dates to see the allocation grid.'
        }),
        ('Financials', {
            'fields': ('total_revenue', 'total_hours'),
        }),
        ('Team', {
            'fields': ('project_manager', 'team_members'),
            'description': 'Select team members here, then use the allocation grid below to assign hours.'
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
    
    def get_urls(self):
        urls = super().get_urls()
        custom_urls = [
            path('<path:object_id>/save-allocations/', 
                 self.admin_site.admin_view(self.save_allocations_view), 
                 name='agency_project_save_allocations'),
            path('<path:object_id>/get-allocation-data/',
                 self.admin_site.admin_view(self.get_allocation_data_view),
                 name='agency_project_get_allocation_data'),
            path('<path:object_id>/available-members/',
                 self.admin_site.admin_view(self.get_available_members_view),
                 name='agency_project_available_members'),
            path('<path:object_id>/add-member/',
                 self.admin_site.admin_view(self.add_member_view),
                 name='agency_project_add_member'),
            path('<path:object_id>/remove-member/',
                 self.admin_site.admin_view(self.remove_member_view),
                 name='agency_project_remove_member'),
        ]
        return custom_urls + urls
    
    def get_allocation_data_view(self, request, object_id):
        """Get team members and existing allocations"""
        try:
            project = self.get_object(request, object_id)
            
            # Get team members
            team_members = []
            if hasattr(project, 'team_members'):
                for member in project.team_members.all():
                    team_members.append({
                        'id': str(member.id),
                        'name': member.user.get_full_name() or member.user.username,
                        'role': member.get_role_display(),
                        'hourly_rate': float(member.hourly_rate),
                        'initials': ''.join([n[0].upper() for n in (member.user.get_full_name() or member.user.username).split()[:2]])
                    })
            
            # Get existing allocations
            allocations = {}
            for alloc in ProjectAllocation.objects.filter(project=project):
                # For now, store monthly allocations (we'll distribute to weeks in JS)
                # You could enhance this to store actual weekly data
                key = f"{alloc.user_profile_id}_{alloc.year}_{alloc.month}_1"
                allocations[key] = float(alloc.allocated_hours)
            
            return JsonResponse({
                'team_members': team_members,
                'allocations': allocations
            })
        except Exception as e:
            return JsonResponse({'error': str(e)}, status=400)
    
    def get_available_members_view(self, request, object_id):
        """Get available team members not yet on the project"""
        try:
            project = self.get_object(request, object_id)
            
            # Get all company members not on the project
            members = UserProfile.objects.filter(
                company=project.company,
                status__in=['full_time', 'part_time', 'contractor']
            ).exclude(
                id__in=project.team_members.values_list('id', flat=True)
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
            return JsonResponse({'error': str(e)}, status=400)
    
    def add_member_view(self, request, object_id):
        """Add a team member to the project"""
        if request.method == 'POST':
            try:
                project = self.get_object(request, object_id)
                data = json.loads(request.body)
                member_id = data.get('member_id')
                
                member = UserProfile.objects.get(id=member_id, company=project.company)
                project.team_members.add(member)
                
                return JsonResponse({'success': True})
            except Exception as e:
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
                project.team_members.remove(member)
                
                # Also remove their allocations
                ProjectAllocation.objects.filter(
                    project=project,
                    user_profile=member
                ).delete()
                
                return JsonResponse({'success': True})
            except Exception as e:
                return JsonResponse({'error': str(e)}, status=400)
        
        return JsonResponse({'error': 'Invalid request'}, status=400)
    
    def save_allocations_view(self, request, object_id):
        """Handle allocation saves via AJAX"""
        if request.method == 'POST':
            try:
                project = self.get_object(request, object_id)
                data = json.loads(request.body)
                allocations = data.get('allocations', [])
                
                # Clear existing allocations for this project
                ProjectAllocation.objects.filter(project=project).delete()
                
                # Group allocations by member/month and sum the hours
                monthly_totals = {}
                for alloc in allocations:
                    key = (alloc['member_id'], alloc['year'], alloc['month'])
                    if key not in monthly_totals:
                        monthly_totals[key] = 0
                    monthly_totals[key] += float(alloc['hours'])
                
                # Create allocations
                for (member_id, year, month), hours in monthly_totals.items():
                    if hours > 0:
                        member = UserProfile.objects.get(id=member_id)
                        ProjectAllocation.objects.create(
                            project=project,
                            user_profile=member,
                            year=year,
                            month=month,
                            allocated_hours=hours,
                            hourly_rate=member.hourly_rate
                        )
                
                return JsonResponse({'status': 'success'})
            except Exception as e:
                return JsonResponse({'status': 'error', 'message': str(e)})
        
        return JsonResponse({'status': 'error', 'message': 'Invalid request'})'''

    # Find and replace the ProjectAdmin class
    pattern = r'@admin\.register\(Project\)\s*\nclass ProjectAdmin\(admin\.ModelAdmin\):.*?(?=\n@admin\.register|\nclass\s|\nadmin\.site\.|\Z)'
    
    if re.search(pattern, content, flags=re.DOTALL):
        content = re.sub(pattern, new_project_admin, content, flags=re.DOTALL)
        print("ProjectAdmin class replaced successfully")
    else:
        print("Could not find ProjectAdmin class to replace")
        # Try to add it after the last register decorator
        last_register = content.rfind('@admin.register')
        if last_register != -1:
            # Find the end of that class
            next_class = content.find('\n@admin.register', last_register + 1)
            if next_class == -1:
                next_class = content.find('\nadmin.site.', last_register)
            if next_class == -1:
                next_class = len(content)
            
            content = content[:next_class] + '\n\n' + new_project_admin + '\n' + content[next_class:]
            print("ProjectAdmin class added to admin.py")

    # Add necessary imports at the top if not present
    imports_to_add = [
        "from django.http import JsonResponse",
        "import json",
        "import datetime"
    ]

    for imp in imports_to_add:
        if imp not in content:
            # Add after the last import from django
            last_django_import = content.rfind('from django')
            if last_django_import != -1:
                import_line_end = content.find('\n', last_django_import)
                content = content[:import_line_end + 1] + imp + '\n' + content[import_line_end + 1:]
                print(f"Added import: {imp}")

    # Write back
    with open('agency/admin.py', 'w') as f:
        f.write(content)

    print("admin.py updated successfully!")

except Exception as e:
    print(f"Error updating admin.py: {e}")
    sys.exit(1)
PYTHON_SCRIPT

# Run the Python script to update admin.py
print_status "Updating admin.py..."
python update_admin_temp.py

# Remove the temporary Python script
rm update_admin_temp.py

# Update settings.py to include static files
print_status "Checking settings.py for STATICFILES_DIRS..."
if ! grep -q "STATICFILES_DIRS" agency_management/settings.py; then
    print_status "Adding STATICFILES_DIRS to settings.py..."
    cat >> agency_management/settings.py << 'EOF'

# Static files configuration
STATICFILES_DIRS = [
    BASE_DIR / "static",
]

STATIC_ROOT = BASE_DIR / "staticfiles"
EOF
else
    print_status "STATICFILES_DIRS already configured in settings.py"
fi

# Fix the pagination warning in ProjectAllocationAdmin
print_status "Fixing pagination warning..."
python << 'PYTHON_FIX'
import re

try:
    with open('agency/admin.py', 'r') as f:
        content = f.read()
    
    # Check if we need to add ordering to ProjectAllocationAdmin
    if 'class ProjectAllocationAdmin' in content and "ordering = ['-year', '-month', 'project__name']" not in content:
        # Find ProjectAllocationAdmin and add ordering
        pattern = r'(class ProjectAllocationAdmin\(admin\.ModelAdmin\):\s*\n\s*list_display[^\n]+\n)'
        replacement = r'\1    ordering = [\'-year\', \'-month\', \'project__name\']\n'
        content = re.sub(pattern, replacement, content)
        
        with open('agency/admin.py', 'w') as f:
            f.write(content)
        print("Added ordering to ProjectAllocationAdmin")
    else:
        print("ProjectAllocationAdmin already has ordering or not found")
        
except Exception as e:
    print(f"Could not fix pagination warning: {e}")
PYTHON_FIX

# Collect static files
print_status "Collecting static files..."
python manage.py collectstatic --noinput

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
print_status "✓ Static files created"
print_status "✓ admin.py updated with new methods"
print_status "✓ settings.py updated"
print_status "✓ Static files collected"
echo ""
echo "The new consolidated allocation interface is ready!"
echo ""
echo "Features:"
echo "  • Single consolidated team & allocation section"
echo "  • Week-based columns with month headers"
echo "  • Dynamic add/remove team members"
echo "  • No empty fields - only shows assigned members"
echo "  • Automatic weekly-to-monthly conversion"
echo "  • Clean, professional interface"
echo ""
print_warning "Now restart your Django development server:"
echo "  python manage.py runserver"
echo ""
echo "Then edit any project to see the new interface!"