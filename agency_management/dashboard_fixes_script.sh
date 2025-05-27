#!/bin/bash

# Dashboard Fixes Script - Remove MonthlyRevenue from admin and fix forecasted revenue chart
set -e

echo "🔧 APPLYING DASHBOARD FIXES..."
echo "================================"

echo "📝 Step 1: Updating admin.py to remove MonthlyRevenue from admin..."

cat > agency/admin.py << 'EOF'
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
EOF

echo "✅ Updated admin.py - MonthlyRevenue removed from admin interface"

echo "📝 Step 2: Updating views.py to fix forecasted revenue chart data..."

cat > agency/views.py << 'EOF'
# agency/views.py - Fixed forecasted revenue chart data
from django.shortcuts import render, get_object_or_404
from django.http import JsonResponse
from django.db.models import Sum, Q, Count
from django.contrib.auth.decorators import login_required
from django.utils import timezone
from datetime import datetime, date
from decimal import Decimal
import json
import calendar

# Import only models that exist
from .models import (
    Company, UserProfile, Client, Project, ProjectAllocation, 
    MonthlyRevenue, Expense, ContractorExpense, Cost, CapacitySnapshot
)

@login_required
def dashboard(request):
    """Enhanced dashboard with comprehensive metrics"""
    try:
        company = Company.objects.first()
        if not company:
            # Create default company if none exists
            company = Company.objects.create(name="Default Company", code="DC")
        
        current_year = datetime.now().year
        current_month = datetime.now().month
        
        # Basic metrics
        total_clients = Client.objects.filter(company=company, status='active').count()
        total_projects = Project.objects.filter(company=company).count()
        
        # Check if revenue_type field exists on Project model
        try:
            booked_projects = Project.objects.filter(company=company, revenue_type='booked').count()
            forecast_projects = Project.objects.filter(company=company, revenue_type='forecast').count()
        except:
            # If revenue_type doesn't exist yet, just count all projects
            booked_projects = total_projects
            forecast_projects = 0
        
        total_team_members = UserProfile.objects.filter(company=company, status='full_time').count()
        
        # Current month revenue from MonthlyRevenue table
        current_revenue = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            month=current_month,
            revenue_type='booked'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        # Annual revenue from MonthlyRevenue table
        annual_booked_revenue = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            revenue_type='booked'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        annual_forecast_revenue = MonthlyRevenue.objects.filter(
            company=company,
            year=current_year,
            revenue_type='forecast'
        ).aggregate(total=Sum('revenue'))['total'] or Decimal('0')
        
        total_annual_revenue = annual_booked_revenue + annual_forecast_revenue
        
        # Monthly costs calculation
        payroll_costs = Decimal('0')
        contractor_costs = Decimal('0')
        other_costs = Decimal('0')
        
        # Calculate payroll costs from team members
        team_members = UserProfile.objects.filter(company=company, status='full_time')
        for member in team_members:
            payroll_costs += member.monthly_salary_cost
        
        # Try to get costs from Cost model if it exists
        try:
            costs_this_month = Cost.objects.filter(
                company=company,
                start_date__lte=date(current_year, current_month, 1),
                is_active=True
            ).filter(
                Q(end_date__isnull=True) | Q(end_date__gte=date(current_year, current_month, 1))
            )
            
            for cost in costs_this_month:
                cost_amount = cost.monthly_amount
                if cost.is_contractor:
                    contractor_costs += cost_amount
                elif cost.cost_type != 'payroll':
                    other_costs += cost_amount
        except:
            # If Cost model doesn't exist, use legacy models
            expenses = Expense.objects.filter(company=company, is_active=True)
            for expense in expenses:
                other_costs += expense.monthly_amount
            
            contractor_expenses = ContractorExpense.objects.filter(
                company=company, year=current_year, month=current_month
            )
            for expense in contractor_expenses:
                contractor_costs += expense.amount
        
        current_month_costs = payroll_costs + contractor_costs + other_costs
        
        # Annual costs
        total_annual_costs = (payroll_costs + contractor_costs + other_costs) * 12
        
        # Profit calculations
        monthly_profit = current_revenue - current_month_costs
        monthly_profit_margin = (monthly_profit / current_revenue * 100) if current_revenue > 0 else Decimal('0')
        
        annual_profit = total_annual_revenue - total_annual_costs
        annual_profit_margin = (annual_profit / total_annual_revenue * 100) if total_annual_revenue > 0 else Decimal('0')
        
        context = {
            'company': company,
            'total_clients': total_clients,
            'total_projects': total_projects,
            'booked_projects': booked_projects,
            'forecast_projects': forecast_projects,
            'total_team_members': total_team_members,
            
            # Revenue metrics
            'current_revenue': current_revenue,
            'annual_booked_revenue': annual_booked_revenue,
            'annual_forecast_revenue': annual_forecast_revenue,
            'total_annual_revenue': total_annual_revenue,
            
            # Cost metrics
            'current_month_costs': current_month_costs,
            'payroll_costs': payroll_costs,
            'contractor_costs': contractor_costs,
            'other_costs': other_costs,
            'total_annual_costs': total_annual_costs,
            
            # Profit metrics
            'monthly_profit': monthly_profit,
            'monthly_profit_margin': monthly_profit_margin,
            'annual_profit': annual_profit,
            'annual_profit_margin': annual_profit_margin,
            
            'current_year': current_year,
            'current_month': current_month,
        }
        
        return render(request, 'dashboard.html', context)
    
    except Exception as e:
        # Fallback context if anything fails
        context = {
            'error': str(e),
            'total_clients': 0,
            'total_projects': 0,
            'current_revenue': Decimal('0'),
            'total_annual_revenue': Decimal('0'),
            'current_month_costs': Decimal('0'),
            'monthly_profit': Decimal('0'),
        }
        return render(request, 'dashboard.html', context)

@login_required
def projects_list(request):
    """List all projects with revenue type filter"""
    company = Company.objects.first()
    revenue_type = request.GET.get('revenue_type', 'all')
    
    projects = Project.objects.filter(company=company).select_related('client')
    
    # Only filter by revenue_type if the field exists
    if revenue_type != 'all':
        try:
            projects = projects.filter(revenue_type=revenue_type)
        except:
            pass  # Field doesn't exist yet
    
    projects = projects.order_by('-created_at')
    
    context = {
        'projects': projects,
        'company': company,
        'current_filter': revenue_type,
    }
    
    return render(request, 'projects/list.html', context)

@login_required
def clients_list(request):
    """List all clients"""
    company = Company.objects.first()
    clients = Client.objects.filter(company=company).order_by('name')
    
    context = {
        'clients': clients,
        'company': company,
    }
    
    return render(request, 'clients/list.html', context)

@login_required
def team_list(request):
    """List all team members"""
    company = Company.objects.first()
    team_members = UserProfile.objects.filter(company=company).select_related('user').order_by('user__last_name')
    
    context = {
        'team_members': team_members,
        'company': company,
    }
    
    return render(request, 'team/list.html', context)

@login_required
def capacity_dashboard(request):
    """Capacity planning dashboard"""
    company = Company.objects.first()
    
    # Calculate current month utilization
    current_year = datetime.now().year
    current_month = datetime.now().month
    
    # Get team capacity
    team_members = UserProfile.objects.filter(company=company, status='full_time')
    total_capacity = sum(
        float(profile.weekly_capacity_hours) * 4.33 
        for profile in team_members
    )
    
    # Get current allocations
    current_allocations = ProjectAllocation.objects.filter(
        project__company=company,
        year=current_year,
        month=current_month
    ).aggregate(total=Sum('allocated_hours'))['total'] or 0
    
    utilization_rate = (float(current_allocations) / total_capacity * 100) if total_capacity > 0 else 0
    
    context = {
        'company': company,
        'total_capacity': total_capacity,
        'current_allocations': current_allocations,
        'utilization_rate': utilization_rate,
        'team_members': team_members,
    }
    
    return render(request, 'capacity.html', context)

@login_required
def revenue_chart_data(request):
    """API endpoint for revenue chart data - FIXED to show forecast data"""
    company = Company.objects.first()
    year = int(request.GET.get('year', datetime.now().year))
    
    try:
        # First try to get data from MonthlyRevenue table
        revenues = MonthlyRevenue.objects.filter(
            company=company,
            year=year
        ).values('month', 'revenue_type').annotate(
            total=Sum('revenue')
        ).order_by('month', 'revenue_type')
        
        # Format data for chart
        monthly_data = {}
        for month in range(1, 13):
            monthly_data[month] = {'booked': 0, 'forecast': 0}
        
        for revenue in revenues:
            month = revenue['month']
            revenue_type = revenue['revenue_type']
            total = float(revenue['total'])
            monthly_data[month][revenue_type] = total
        
        # If no MonthlyRevenue data, try to calculate from Projects
        has_data = any(monthly_data[m]['booked'] > 0 or monthly_data[m]['forecast'] > 0 for m in range(1, 13))
        
        if not has_data:
            # Calculate revenue from Projects distributed across months
            projects = Project.objects.filter(company=company)
            
            for project in projects:
                try:
                    # Check if project has revenue_type field
                    revenue_type = getattr(project, 'revenue_type', 'booked')
                    
                    # Calculate monthly distribution
                    start_date = project.start_date
                    end_date = project.end_date
                    
                    if start_date.year <= year <= end_date.year:
                        # Calculate how many months this project spans in the given year
                        year_start = max(start_date, date(year, 1, 1))
                        year_end = min(end_date, date(year, 12, 31))
                        
                        # Calculate months in year
                        months_in_year = []
                        current_date = year_start.replace(day=1)
                        while current_date <= year_end:
                            if current_date.year == year:
                                months_in_year.append(current_date.month)
                            # Move to next month
                            if current_date.month == 12:
                                current_date = current_date.replace(year=current_date.year + 1, month=1)
                            else:
                                current_date = current_date.replace(month=current_date.month + 1)
                        
                        if months_in_year:
                            monthly_revenue = float(project.total_revenue) / len(months_in_year)
                            for month in months_in_year:
                                monthly_data[month][revenue_type] += monthly_revenue
                
                except Exception as e:
                    # Skip projects that cause errors
                    continue
        
        # Convert to lists for chart
        months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        booked_data = [monthly_data[i+1]['booked'] for i in range(12)]
        forecast_data = [monthly_data[i+1]['forecast'] for i in range(12)]
        
        return JsonResponse({
            'months': months,
            'booked': booked_data,
            'forecast': forecast_data,
            'year': year
        })
    
    except Exception as e:
        # Return empty data if anything fails
        months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        return JsonResponse({
            'months': months,
            'booked': [0] * 12,
            'forecast': [0] * 12,
            'year': year,
            'error': str(e)
        })

def health_check(request):
    """Simple health check endpoint"""
    return JsonResponse({'status': 'ok', 'timestamp': datetime.now().isoformat()})

# Additional view stubs for URLs
def client_detail(request, client_id):
    """Client detail view"""
    return JsonResponse({'error': 'Not implemented yet'})

def project_detail(request, project_id):
    """Project detail view"""
    return JsonResponse({'error': 'Not implemented yet'})

def import_data(request):
    """Import data from spreadsheet"""
    return JsonResponse({'error': 'Not implemented yet'})

def capacity_chart_data(request):
    """API endpoint for capacity chart data"""
    return JsonResponse({'error': 'Not implemented yet'})
EOF

echo "✅ Updated views.py - Fixed forecasted revenue chart data calculation"

echo "📝 Step 3: Adding project template for better project management..."

# Create projects directory if it doesn't exist
mkdir -p templates/projects

cat > templates/projects/list.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Projects - Agency Management</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
</head>
<body class="bg-gray-100">
    <div class="min-h-screen">
        <!-- Header -->
        <header class="bg-white shadow">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div class="flex justify-between items-center py-6">
                    <div class="flex items-center">
                        <a href="{% url 'agency:dashboard' %}" class="text-blue-600 hover:text-blue-800 mr-4">
                            <i class="fas fa-arrow-left"></i> Back to Dashboard
                        </a>
                        <h1 class="text-3xl font-bold text-gray-900">Projects</h1>
                        {% if company %}
                            <span class="ml-4 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">{{ company.name }}</span>
                        {% endif %}
                    </div>
                    <div class="flex space-x-4">
                        <a href="/admin/agency/project/add/" class="bg-blue-500 text-white px-4 py-2 rounded-md hover:bg-blue-600">
                            <i class="fas fa-plus mr-2"></i>Add Project
                        </a>
                    </div>
                </div>
            </div>
        </header>

        <!-- Main Content -->
        <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            
            <!-- Filter Tabs -->
            <div class="mb-6">
                <div class="border-b border-gray-200">
                    <nav class="-mb-px flex space-x-8">
                        <a href="{% url 'agency:projects_list' %}" 
                           class="{% if current_filter == 'all' %}border-blue-500 text-blue-600{% else %}border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300{% endif %} whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">
                            All Projects
                        </a>
                        <a href="{% url 'agency:projects_list' %}?revenue_type=booked" 
                           class="{% if current_filter == 'booked' %}border-blue-500 text-blue-600{% else %}border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300{% endif %} whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">
                            <i class="fas fa-check-circle mr-1"></i>Booked Projects
                        </a>
                        <a href="{% url 'agency:projects_list' %}?revenue_type=forecast" 
                           class="{% if current_filter == 'forecast' %}border-blue-500 text-blue-600{% else %}border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300{% endif %} whitespace-nowrap py-2 px-1 border-b-2 font-medium text-sm">
                            <i class="fas fa-clock mr-1"></i>Forecast Projects
                        </a>
                    </nav>
                </div>
            </div>

            <!-- Projects List -->
            <div class="bg-white shadow overflow-hidden sm:rounded-md">
                <ul class="divide-y divide-gray-200">
                    {% for project in projects %}
                    <li>
                        <div class="px-4 py-4 flex items-center justify-between">
                            <div class="flex items-center">
                                <div class="flex-shrink-0">
                                    {% if project.revenue_type == 'booked' %}
                                        <i class="fas fa-check-circle text-green-500 text-xl"></i>
                                    {% elif project.revenue_type == 'forecast' %}
                                        <i class="fas fa-clock text-yellow-500 text-xl"></i>
                                    {% else %}
                                        <i class="fas fa-project-diagram text-blue-500 text-xl"></i>
                                    {% endif %}
                                </div>
                                <div class="ml-4">
                                    <div class="flex items-center">
                                        <div class="text-lg font-medium text-gray-900">
                                            {{ project.name }}
                                        </div>
                                        <div class="ml-2 flex-shrink-0 flex">
                                            <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full 
                                                {% if project.status == 'active' %}bg-green-100 text-green-800{% elif project.status == 'planning' %}bg-yellow-100 text-yellow-800{% elif project.status == 'completed' %}bg-blue-100 text-blue-800{% else %}bg-gray-100 text-gray-800{% endif %}">
                                                {{ project.get_status_display }}
                                            </span>
                                        </div>
                                    </div>
                                    <div class="text-sm text-gray-500">
                                        <span class="font-medium">{{ project.client.name }}</span>
                                        <span class="mx-2">•</span>
                                        <span>${{ project.total_revenue|floatformat:0 }}</span>
                                        <span class="mx-2">•</span>
                                        <span>{{ project.start_date }} - {{ project.end_date }}</span>
                                        {% if project.revenue_type %}
                                            <span class="mx-2">•</span>
                                            <span class="capitalize font-medium
                                                {% if project.revenue_type == 'booked' %}text-green-600{% else %}text-yellow-600{% endif %}">
                                                {{ project.revenue_type }}
                                            </span>
                                        {% endif %}
                                    </div>
                                </div>
                            </div>
                            <div class="flex items-center space-x-2">
                                <a href="/admin/agency/project/{{ project.id }}/change/" 
                                   class="text-blue-600 hover:text-blue-900">
                                    <i class="fas fa-edit"></i>
                                </a>
                            </div>
                        </div>
                    </li>
                    {% empty %}
                    <li>
                        <div class="px-4 py-8 text-center">
                            <i class="fas fa-project-diagram text-gray-400 text-4xl mb-4"></i>
                            <h3 class="text-lg font-medium text-gray-900 mb-2">No projects found</h3>
                            <p class="text-gray-500 mb-4">Get started by creating your first project.</p>
                            <a href="/admin/agency/project/add/" 
                               class="bg-blue-500 text-white px-4 py-2 rounded-md hover:bg-blue-600">
                                <i class="fas fa-plus mr-2"></i>Add Project
                            </a>
                        </div>
                    </li>
                    {% endfor %}
                </ul>
            </div>

            <!-- Summary Stats -->
            {% if projects %}
            <div class="mt-8 grid grid-cols-1 md:grid-cols-3 gap-6">
                <div class="bg-white rounded-lg shadow p-6">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-blue-600">{{ projects|length }}</p>
                        <p class="text-sm text-gray-600">
                            {% if current_filter == 'all' %}Total Projects{% elif current_filter == 'booked' %}Booked Projects{% elif current_filter == 'forecast' %}Forecast Projects{% else %}Projects{% endif %}
                        </p>
                    </div>
                </div>
                <div class="bg-white rounded-lg shadow p-6">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-green-600">
                            $<span id="totalRevenue">0</span>
                        </p>
                        <p class="text-sm text-gray-600">Total Revenue</p>
                    </div>
                </div>
                <div class="bg-white rounded-lg shadow p-6">
                    <div class="text-center">
                        <p class="text-2xl font-bold text-purple-600">
                            <span id="avgRevenue">$0</span>
                        </p>
                        <p class="text-sm text-gray-600">Average Revenue</p>
                    </div>
                </div>
            </div>
            {% endif %}
        </main>
    </div>

    <script>
    document.addEventListener('DOMContentLoaded', function() {
        // Calculate total and average revenue
        const projects = [
            {% for project in projects %}
            { revenue: {{ project.total_revenue|default:0 }} },
            {% endfor %}
        ];
        
        const totalRevenue = projects.reduce((sum, project) => sum + project.revenue, 0);
        const avgRevenue = projects.length > 0 ? totalRevenue / projects.length : 0;
        
        // Format and display
        document.getElementById('totalRevenue').textContent = 
            new Intl.NumberFormat('en-US').format(Math.round(totalRevenue));
        document.getElementById('avgRevenue').textContent = 
            new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', minimumFractionDigits: 0 }).format(Math.round(avgRevenue));
    });
    </script>
</body>
</html>
EOF

echo "✅ Created projects list template"

echo "📝 Step 4: Testing fixes..."

# Test Django startup
python manage.py check

if [ $? -eq 0 ]; then
    echo "✅ Django checks passed!"
else
    echo "❌ Django checks failed"
    exit 1
fi

echo ""
echo "🎉 DASHBOARD FIXES COMPLETED!"
echo "============================"
echo ""
echo "✅ WHAT WAS FIXED:"
echo "  ✓ Removed MonthlyRevenue from admin interface"
echo "  ✓ Fixed forecasted revenue chart - now shows both booked and forecast data"
echo "  ✓ Enhanced revenue chart to fallback to Project data if MonthlyRevenue is empty"
echo "  ✓ Added better project list template with revenue type filtering"
echo "  ✓ Chart now distributes project revenue across project duration months"
echo ""
echo "🚀 NEXT STEPS:"
echo "  1. Restart your server:"
echo "     python manage.py runserver"
echo ""
echo "  2. Check your dashboard - forecasted revenue should now chart properly"
echo ""
echo "  3. MonthlyRevenue is no longer in admin - manage revenue through Projects"
echo ""
echo "💡 The chart will now show:"
echo "   - Booked projects in GREEN"
echo "   - Forecast projects in BLUE"
echo "   - Revenue distributed across project duration"
echo ""