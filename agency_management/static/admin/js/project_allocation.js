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
