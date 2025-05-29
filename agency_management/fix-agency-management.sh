#!/bin/bash

# Fix Dashboard Script - Applies all dashboard and chart fixes
# Usage: ./fix_dashboard.sh

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}     Dashboard & Chart Fix Script${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_header

# 1. Create necessary directories
print_info "Creating directory structure..."
mkdir -p templates
mkdir -p agency/management/commands
touch agency/management/__init__.py
touch agency/management/commands/__init__.py
print_success "Directories created"

# 2. Create .gitignore
print_info "Creating .gitignore..."
cat > .gitignore << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
ENV/
env.bak/
venv.bak/
.venv
pip-log.txt
pip-delete-this-directory.txt
.pytest_cache/
.coverage
.coverage.*
coverage.xml
*.cover
.hypothesis/

# Django
*.log
*.pot
*.pyc
local_settings.py
db.sqlite3
db.sqlite3-journal
media/
staticfiles/
*.sqlite3

# Shell scripts
*.sh

# IDE
.vscode/
.idea/
*.swp
*.swo
*~
.project
.pydevproject
.settings/
*.sublime-project
*.sublime-workspace

# OS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Backup files
*.backup
*.backup.*
*.bak
*.orig
*.rej

# Test files
test_*.py
debug_*.py
*_test.py
*_debug.py
update_*.py
setup_*.py

# Temporary files
*.tmp
*.temp
.~*

# Documentation
docs/_build/
site/

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
MANIFEST

# Virtual environments
bin/
include/
lib/
lib64/
share/
pyvenv.cfg

# Instance-specific files
instance/
.webassets-cache

# Secret files
.env
.env.*
secrets/
*.key
*.pem

# Cache
.cache/
.mypy_cache/
.dmypy.json
dmypy.json

# Logs
logs/
*.log.*

# Generated files
*.pid
*.seed
*.pid.lock

# npm (if using any JS)
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Static files collection
/static/
!/static/admin/

# Media files
/media/

# Local development
local/
tmp/
EOF
print_success ".gitignore created"

# 3. Create base.html template
print_info "Creating base.html template..."
cat > templates/base.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Agency Management System{% endblock %}</title>
    
    <!-- Tailwind CSS -->
    <script src="https://cdn.tailwindcss.com"></script>
    
    <!-- Font Awesome -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <!-- Base styles -->
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background-color: #f3f4f6;
        }
        .nav-link {
            padding: 0.5rem 1rem;
            border-radius: 0.375rem;
            transition: background-color 0.2s;
        }
        .nav-link:hover {
            background-color: rgba(255, 255, 255, 0.1);
        }
        .nav-link.active {
            background-color: rgba(255, 255, 255, 0.2);
        }
    </style>
    
    {% block extra_css %}{% endblock %}
</head>
<body>
    <!-- Navigation -->
    <nav class="bg-gray-800 text-white shadow-lg">
        <div class="container mx-auto px-4">
            <div class="flex items-center justify-between h-16">
                <div class="flex items-center">
                    <a href="{% url 'agency:dashboard' %}" class="text-xl font-bold">
                        <i class="fas fa-chart-line mr-2"></i>
                        Agency Manager
                    </a>
                    
                    <div class="ml-10 flex items-baseline space-x-4">
                        <a href="{% url 'agency:dashboard' %}" class="nav-link {% if request.resolver_match.url_name == 'dashboard' %}active{% endif %}">
                            Dashboard
                        </a>
                        <a href="{% url 'agency:projects_list' %}" class="nav-link {% if 'project' in request.resolver_match.url_name %}active{% endif %}">
                            Projects
                        </a>
                        <a href="{% url 'agency:clients_list' %}" class="nav-link {% if 'client' in request.resolver_match.url_name %}active{% endif %}">
                            Clients
                        </a>
                        <a href="{% url 'agency:team_list' %}" class="nav-link {% if 'team' in request.resolver_match.url_name %}active{% endif %}">
                            Team
                        </a>
                        <a href="{% url 'agency:capacity_dashboard' %}" class="nav-link {% if 'capacity' in request.resolver_match.url_name %}active{% endif %}">
                            Capacity
                        </a>
                    </div>
                </div>
                
                <div class="flex items-center space-x-4">
                    <span class="text-sm">
                        <i class="fas fa-user mr-1"></i>
                        {{ user.get_full_name|default:user.username }}
                    </span>
                    <a href="/admin/" class="text-sm hover:text-gray-300">
                        <i class="fas fa-cog mr-1"></i>
                        Admin
                    </a>
                </div>
            </div>
        </div>
    </nav>
    
    <!-- Main Content -->
    <main>
        {% if messages %}
        <div class="container mx-auto px-4 mt-4">
            {% for message in messages %}
            <div class="alert alert-{{ message.tags }} bg-{{ message.tags }}-100 border border-{{ message.tags }}-400 text-{{ message.tags }}-700 px-4 py-3 rounded mb-4" role="alert">
                <span class="block sm:inline">{{ message }}</span>
            </div>
            {% endfor %}
        </div>
        {% endif %}
        
        {% block content %}{% endblock %}
    </main>
    
    <!-- Footer -->
    <footer class="bg-gray-800 text-white mt-12 py-6">
        <div class="container mx-auto px-4 text-center text-sm">
            <p>&copy; {% now "Y" %} Agency Management System. All rights reserved.</p>
        </div>
    </footer>
    
    {% block extra_js %}{% endblock %}
</body>
</html>
EOF
print_success "base.html created"

# 4. Create dashboard.html template
print_info "Creating dashboard.html template..."
cat > templates/dashboard.html << 'EOF'
{% extends 'base.html' %}
{% load static %}

{% block title %}Dashboard - {{ company.name }}{% endblock %}

{% block extra_css %}
<style>
    .metric-card {
        background: white;
        border-radius: 8px;
        padding: 1.5rem;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        transition: transform 0.2s;
    }
    .metric-card:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 6px rgba(0,0,0,0.1);
    }
    .metric-value {
        font-size: 2rem;
        font-weight: bold;
        margin: 0.5rem 0;
    }
    .metric-label {
        color: #666;
        font-size: 0.875rem;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }
    .positive {
        color: #10b981;
    }
    .negative {
        color: #ef4444;
    }
    .chart-container {
        background: white;
        border-radius: 8px;
        padding: 1.5rem;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        margin-top: 2rem;
        height: 400px;
    }
    .filter-controls {
        display: flex;
        gap: 1rem;
        align-items: center;
        margin-bottom: 1rem;
    }
    .filter-controls select {
        padding: 0.5rem 1rem;
        border: 1px solid #ddd;
        border-radius: 4px;
        background: white;
        cursor: pointer;
    }
    .user-switcher {
        position: relative;
        margin-left: auto;
    }
    .user-switcher select {
        padding: 0.5rem 1rem;
        border: 1px solid #ddd;
        border-radius: 4px;
        background: white;
        cursor: pointer;
        min-width: 200px;
    }
    .viewing-as {
        background: #fef3c7;
        padding: 0.5rem 1rem;
        border-radius: 4px;
        font-size: 0.875rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
    }
    .revenue-type-badge {
        display: inline-block;
        padding: 0.25rem 0.75rem;
        border-radius: 4px;
        font-size: 0.75rem;
        font-weight: 500;
        margin-left: 0.5rem;
    }
    .badge-booked {
        background: #dbeafe;
        color: #1e40af;
    }
    .badge-forecast {
        background: #fef3c7;
        color: #92400e;
    }
</style>
{% endblock %}

{% block content %}
<div class="container mx-auto px-4 py-8">
    <!-- Header with User Switcher -->
    <div class="flex justify-between items-center mb-8">
        <div>
            <h1 class="text-3xl font-bold">{{ company.name }} Dashboard</h1>
            <p class="text-gray-600">Real-time agency metrics and insights</p>
        </div>
        
        {% if user.is_superuser %}
        <div class="user-switcher">
            {% if request.session.viewing_as_user %}
            <div class="viewing-as">
                <span>Viewing as another user</span>
                <a href="{% url 'agency:switch_back' %}" class="text-blue-600 hover:underline">Switch back to admin</a>
            </div>
            {% else %}
            <select id="userSwitcher" onchange="switchUserView(this.value)" class="form-select">
                <option value="">View as user...</option>
                {% for profile in all_profiles %}
                <option value="{{ profile.user.id }}">
                    {{ profile.user.get_full_name|default:profile.user.username }}
                    {% if profile.is_project_manager %}(PM){% endif %}
                </option>
                {% endfor %}
            </select>
            {% endif %}
        </div>
        {% endif %}
    </div>

    <!-- Key Metrics Grid -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <!-- Revenue Card -->
        <div class="metric-card">
            <div class="metric-label">Monthly Revenue</div>
            <div class="metric-value">${{ current_revenue|floatformat:0|default:"0" }}</div>
            <div class="text-sm text-gray-600">
                <span class="revenue-type-badge badge-booked">Booked</span>
            </div>
        </div>

        <!-- Annual Revenue Card -->
        <div class="metric-card">
            <div class="metric-label">Annual Revenue</div>
            <div class="metric-value">${{ total_annual_revenue|floatformat:0|default:"0" }}</div>
            <div class="text-sm text-gray-600">
                <span class="text-blue-600">${{ annual_booked_revenue|floatformat:0 }}</span> booked
                <span class="text-yellow-600 ml-2">${{ annual_forecast_revenue|floatformat:0 }}</span> forecast
            </div>
        </div>

        <!-- Costs Card -->
        <div class="metric-card">
            <div class="metric-label">Monthly Operating Costs</div>
            <div class="metric-value negative">${{ current_month_costs|floatformat:0|default:"0" }}</div>
            <div class="text-sm text-gray-600">
                Payroll: ${{ payroll_costs|floatformat:0 }}
            </div>
        </div>

        <!-- Profit Card -->
        <div class="metric-card">
            <div class="metric-label">Monthly Profit</div>
            <div class="metric-value {% if monthly_profit > 0 %}positive{% else %}negative{% endif %}">
                ${{ monthly_profit|floatformat:0|default:"0" }}
            </div>
            <div class="text-sm text-gray-600">
                Margin: {{ monthly_profit_margin|floatformat:1 }}%
            </div>
        </div>
    </div>

    <!-- Secondary Metrics -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
        <div class="bg-white p-4 rounded-lg shadow">
            <div class="text-2xl font-bold">{{ total_clients }}</div>
            <div class="text-sm text-gray-600">Active Clients</div>
        </div>
        <div class="bg-white p-4 rounded-lg shadow">
            <div class="text-2xl font-bold">{{ total_projects }}</div>
            <div class="text-sm text-gray-600">Total Projects</div>
            <div class="text-xs text-gray-500">
                {{ booked_projects }} booked, {{ forecast_projects }} forecast
            </div>
        </div>
        <div class="bg-white p-4 rounded-lg shadow">
            <div class="text-2xl font-bold">{{ total_team_members }}</div>
            <div class="text-sm text-gray-600">Team Members</div>
        </div>
        <div class="bg-white p-4 rounded-lg shadow">
            <div class="text-2xl font-bold {% if annual_profit > 0 %}text-green-600{% else %}text-red-600{% endif %}">
                {{ annual_profit_margin|floatformat:1 }}%
            </div>
            <div class="text-sm text-gray-600">Annual Profit Margin</div>
        </div>
    </div>

    <!-- Revenue Chart -->
    <div class="chart-container">
        <div class="filter-controls">
            <h2 class="text-xl font-bold">Revenue & Operating Expenses</h2>
            <select id="yearFilter" class="ml-auto">
                <option value="2023" {% if current_year == 2023 %}selected{% endif %}>2023</option>
                <option value="2024" {% if current_year == 2024 %}selected{% endif %}>2024</option>
                <option value="2025" {% if current_year == 2025 %}selected{% endif %}>2025</option>
                <option value="2026" {% if current_year == 2026 %}selected{% endif %}>2026</option>
            </select>
            <select id="viewFilter">
                <option value="combined">Combined View</option>
                <option value="stacked">Stacked View</option>
                <option value="separate">Separate Lines</option>
            </select>
        </div>
        <canvas id="revenueChart" style="max-height: 300px;"></canvas>
    </div>

    <!-- Quick Actions -->
    <div class="mt-8 grid grid-cols-1 md:grid-cols-3 gap-4">
        <a href="{% url 'agency:projects_list' %}" class="bg-blue-600 text-white p-4 rounded-lg text-center hover:bg-blue-700 transition">
            <div class="text-lg font-semibold">View Projects</div>
            <div class="text-sm opacity-90">Manage active projects</div>
        </a>
        <a href="{% url 'agency:clients_list' %}" class="bg-green-600 text-white p-4 rounded-lg text-center hover:bg-green-700 transition">
            <div class="text-lg font-semibold">View Clients</div>
            <div class="text-sm opacity-90">Client relationships</div>
        </a>
        <a href="{% url 'agency:capacity_dashboard' %}" class="bg-purple-600 text-white p-4 rounded-lg text-center hover:bg-purple-700 transition">
            <div class="text-lg font-semibold">Capacity Planning</div>
            <div class="text-sm opacity-90">Team utilization</div>
        </a>
    </div>
</div>

<!-- Chart.js -->
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script>
// Global chart variable
let revenueChart = null;

// Initialize chart when page loads
document.addEventListener('DOMContentLoaded', function() {
    initializeChart();
    
    // Add event listeners for filters
    document.getElementById('yearFilter').addEventListener('change', updateChart);
    document.getElementById('viewFilter').addEventListener('change', updateChart);
});

function initializeChart() {
    const ctx = document.getElementById('revenueChart').getContext('2d');
    
    revenueChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
            datasets: []
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
                mode: 'index',
                intersect: false,
            },
            plugins: {
                legend: {
                    display: true,
                    position: 'top',
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            let label = context.dataset.label || '';
                            if (label) {
                                label += ': ';
                            }
                            label += '$' + context.parsed.y.toLocaleString();
                            return label;
                        }
                    }
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        callback: function(value) {
                            return '$' + value.toLocaleString();
                        }
                    }
                }
            }
        }
    });
    
    // Load initial data
    updateChart();
}

function updateChart() {
    const year = document.getElementById('yearFilter').value;
    const viewType = document.getElementById('viewFilter').value;
    
    // Show loading state
    document.getElementById('revenueChart').style.opacity = '0.5';
    
    fetch(`{% url 'agency:revenue_chart_data' %}?year=${year}`)
        .then(response => response.json())
        .then(data => {
            // Update chart based on view type
            let datasets = [];
            
            if (viewType === 'combined') {
                // Show combined revenue (booked + forecast) and expenses
                datasets = [
                    {
                        label: 'Total Revenue',
                        data: data.combined || data.months.map((_, i) => (data.booked[i] + data.forecast[i])),
                        borderColor: 'rgb(59, 130, 246)',
                        backgroundColor: 'rgba(59, 130, 246, 0.1)',
                        tension: 0.1,
                        fill: true
                    },
                    {
                        label: 'Operating Expenses',
                        data: data.expenses,
                        borderColor: 'rgb(239, 68, 68)',
                        backgroundColor: 'rgba(239, 68, 68, 0.1)',
                        tension: 0.1,
                        fill: true
                    }
                ];
            } else if (viewType === 'stacked') {
                // Show stacked booked and forecast revenue
                revenueChart.config.type = 'bar';
                datasets = [
                    {
                        label: 'Booked Revenue',
                        data: data.booked,
                        backgroundColor: 'rgba(59, 130, 246, 0.8)',
                        stack: 'revenue'
                    },
                    {
                        label: 'Forecast Revenue',
                        data: data.forecast,
                        backgroundColor: 'rgba(251, 191, 36, 0.8)',
                        stack: 'revenue'
                    },
                    {
                        label: 'Operating Expenses',
                        data: data.expenses,
                        backgroundColor: 'rgba(239, 68, 68, 0.8)',
                        stack: 'expenses'
                    }
                ];
            } else {
                // Show separate lines for everything
                revenueChart.config.type = 'line';
                datasets = [
                    {
                        label: 'Booked Revenue',
                        data: data.booked,
                        borderColor: 'rgb(59, 130, 246)',
                        backgroundColor: 'rgba(59, 130, 246, 0.1)',
                        tension: 0.1
                    },
                    {
                        label: 'Forecast Revenue',
                        data: data.forecast,
                        borderColor: 'rgb(251, 191, 36)',
                        backgroundColor: 'rgba(251, 191, 36, 0.1)',
                        tension: 0.1
                    },
                    {
                        label: 'Operating Expenses',
                        data: data.expenses,
                        borderColor: 'rgb(239, 68, 68)',
                        backgroundColor: 'rgba(239, 68, 68, 0.1)',
                        tension: 0.1
                    }
                ];
            }
            
            // Update chart data
            revenueChart.data.labels = data.months;
            revenueChart.data.datasets = datasets;
            revenueChart.update();
            
            // Remove loading state
            document.getElementById('revenueChart').style.opacity = '1';
            
            // Log debug info
            console.log('Chart updated with data:', data);
        })
        .catch(error => {
            console.error('Error loading chart data:', error);
            document.getElementById('revenueChart').style.opacity = '1';
        });
}

// User switcher function
function switchUserView(userId) {
    if (userId) {
        window.location.href = `{% url 'agency:switch_user_view' %}?user_id=${userId}`;
    }
}
</script>
{% endblock %}
EOF
print_success "dashboard.html created"

# 5. Create the test revenue generation command
print_info "Creating generate_test_revenue management command..."
cat > agency/management/commands/generate_test_revenue.py << 'EOF'
from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import date, timedelta
from decimal import Decimal
import random
from agency.models import Company, MonthlyRevenue, Project, Client, Cost, UserProfile

class Command(BaseCommand):
    help = 'Generate test revenue data across multiple years'

    def add_arguments(self, parser):
        parser.add_argument(
            '--years',
            type=str,
            default='2023,2024,2025',
            help='Comma-separated list of years to generate data for'
        )
        parser.add_argument(
            '--clear',
            action='store_true',
            help='Clear existing data before generating'
        )

    def handle(self, *args, **options):
        company = Company.objects.first()
        if not company:
            self.stdout.write(self.style.ERROR('No company found. Please create a company first.'))
            return

        years = [int(y.strip()) for y in options['years'].split(',')]
        
        if options['clear']:
            self.stdout.write('Clearing existing monthly revenue data...')
            MonthlyRevenue.objects.filter(company=company).delete()
            self.stdout.write(self.style.SUCCESS('Cleared existing data'))

        self.stdout.write(f'Generating revenue data for years: {years}')

        for year in years:
            self.generate_year_data(company, year)

        self.stdout.write(self.style.SUCCESS('Successfully generated test revenue data'))

    def generate_year_data(self, company, year):
        """Generate monthly revenue data for a specific year"""
        
        # Base values that grow over time
        base_booked = 150000 + (year - 2023) * 50000
        base_forecast = 50000 + (year - 2023) * 20000
        
        # Seasonal factors (higher in Q2 and Q4)
        seasonal_factors = [
            0.85, 0.90, 0.95,  # Q1
            1.05, 1.10, 1.15,  # Q2
            0.95, 0.90, 0.95,  # Q3
            1.10, 1.15, 1.20   # Q4
        ]
        
        for month in range(1, 13):
            # Calculate revenue with some randomness
            seasonal_factor = seasonal_factors[month - 1]
            
            booked_revenue = Decimal(
                base_booked * seasonal_factor * (0.9 + random.random() * 0.2)
            )
            forecast_revenue = Decimal(
                base_forecast * seasonal_factor * (0.8 + random.random() * 0.4)
            )
            
            # Create or update monthly revenue records
            MonthlyRevenue.objects.update_or_create(
                company=company,
                year=year,
                month=month,
                revenue_type='booked',
                defaults={'revenue': booked_revenue}
            )
            
            MonthlyRevenue.objects.update_or_create(
                company=company,
                year=year,
                month=month,
                revenue_type='forecast',
                defaults={'revenue': forecast_revenue}
            )
            
            self.stdout.write(
                f'  {year}-{month:02d}: '
                f'Booked ${booked_revenue:,.0f}, '
                f'Forecast ${forecast_revenue:,.0f}'
            )
        
        # Also generate some projects for this year
        self.generate_projects(company, year)
        
        # Generate costs if they don't exist
        self.generate_costs(company, year)

    def generate_projects(self, company, year):
        """Generate some test projects for the year"""
        
        # Get or create test clients
        client_names = ['Acme Corp', 'TechStart Inc', 'Global Solutions', 'Digital Ventures']
        clients = []
        
        for name in client_names:
            client, _ = Client.objects.get_or_create(
                company=company,
                name=name,
                defaults={
                    'status': 'active'
                }
            )
            clients.append(client)
        
        # Generate 3-5 projects per quarter
        project_count = 0
        for quarter in range(4):
            num_projects = random.randint(3, 5)
            
            for _ in range(num_projects):
                month = quarter * 3 + random.randint(1, 3)
                start_date = date(year, month, 1)
                
                # Project duration 1-6 months
                duration_months = random.randint(1, 6)
                end_date = start_date + timedelta(days=duration_months * 30)
                
                # Revenue based on duration
                base_monthly = random.randint(30000, 80000)
                total_revenue = Decimal(base_monthly * duration_months)
                total_hours = Decimal(duration_months * 160)  # Approx hours
                
                project_count += 1
                project_name = f"{year} Project {project_count}"
                
                # 70% booked, 30% forecast
                revenue_type = 'booked' if random.random() < 0.7 else 'forecast'
                
                Project.objects.create(
                    company=company,
                    name=project_name,
                    client=random.choice(clients),
                    start_date=start_date,
                    end_date=end_date,
                    total_revenue=total_revenue,
                    total_hours=total_hours,
                    revenue_type=revenue_type,
                    status='active' if end_date >= timezone.now().date() else 'completed'
                )
        
        self.stdout.write(f'  Created {project_count} projects for {year}')

    def generate_costs(self, company, year):
        """Generate operating costs if they don't exist"""
        
        # Check if we already have costs
        existing_costs = Cost.objects.filter(company=company).exists()
        if existing_costs:
            return
        
        # Base costs
        cost_items = [
            ('Office Rent', 'rent', 15000),
            ('Software Licenses', 'software', 5000),
            ('Insurance', 'insurance', 3000),
            ('Marketing', 'marketing', 8000),
            ('Professional Services', 'professional', 4000),
            ('Utilities', 'utilities', 2000),
            ('Equipment', 'office', 3000),
        ]
        
        for name, cost_type, amount in cost_items:
            Cost.objects.create(
                company=company,
                name=name,
                cost_type=cost_type,
                amount=Decimal(amount),
                frequency='monthly',
                start_date=date(2023, 1, 1),
                is_active=True
            )
        
        self.stdout.write(f'  Created {len(cost_items)} cost items')
EOF
print_success "generate_test_revenue.py created"

# 6. Backup existing views.py
print_info "Backing up existing views.py..."
if [ -f "agency/views.py" ]; then
    cp agency/views.py agency/views.py.backup.$(date +%Y%m%d_%H%M%S)
    print_success "Backed up views.py"
fi

# 7. Add is_project_manager field to models if missing
print_info "Checking models.py for is_project_manager field..."
if ! grep -q "is_project_manager" agency/models.py; then
    print_info "Adding is_project_manager field to UserProfile model..."
    
    # Find the line with utilization_target and add the new field after it
    sed -i.bak '/utilization_target = models.DecimalField/a\    is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")' agency/models.py
    
    print_success "Added is_project_manager field to models.py"
else
    print_success "is_project_manager field already exists"
fi

# 8. Run migrations
print_info "Running migrations..."
python manage.py makemigrations
python manage.py migrate
print_success "Migrations completed"

# 9. Generate test revenue data
print_info "Generating test revenue data for years 2023-2025..."
python manage.py generate_test_revenue --years="2023,2024,2025" --clear
print_success "Test revenue data generated"

# 10. Clean up backup files
print_info "Cleaning up old backup files..."
find . -name "*.backup.*" -type f -mtime +7 -delete 2>/dev/null || true
find . -name "*.bak" -type f -mtime +7 -delete 2>/dev/null || true
print_success "Cleanup completed"

print_header
print_success "All dashboard fixes applied successfully!"
print_info "Next steps:"
echo "  1. Run the server: python manage.py runserver"
echo "  2. Visit: http://127.0.0.1:8000/"
echo "  3. Test the year filter dropdown (2023-2025)"
echo "  4. Test the view type dropdown (Combined/Stacked/Separate)"
echo "  5. The chart should update dynamically when filters change"
echo ""
print_info "Note: Make sure to update your views.py with the fixed version if needed"
EOF

# Make the script executable
chmod +x fix_dashboard.sh
print_success "Created fix_dashboard.sh - Run it with: ./fix_dashboard.sh"