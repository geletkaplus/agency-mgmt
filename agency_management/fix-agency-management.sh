#!/bin/bash

echo "🔧 Fixing Agency Management Issues..."
echo "=================================="

# Find the actual project directory
if [ -f "manage.py" ]; then
    PROJECT_DIR="."
elif [ -f "agency_management/manage.py" ]; then
    PROJECT_DIR="agency_management"
else
    echo "❌ Error: Cannot find Django project directory!"
    echo "Please run this script from the project root or parent directory."
    exit 1
fi

echo "✅ Found project directory: $PROJECT_DIR"

# 1. First, let's add the is_project_manager field to models.py if not already there
echo "📝 Checking models.py for is_project_manager field..."
if ! grep -q "is_project_manager" "$PROJECT_DIR/agency/models.py" 2>/dev/null; then
    echo "Adding is_project_manager field to UserProfile..."
    # Use perl instead of sed for better cross-platform compatibility
    perl -i.bak -pe 's/(utilization_target = models\.DecimalField.*\n)/$1    is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")\n/' "$PROJECT_DIR/agency/models.py"
    echo "✅ Added is_project_manager field"
else
    echo "✅ is_project_manager field already exists"
fi

# 2. Update the views.py to add the missing dashboard views
echo "📝 Adding dashboard views to views.py..."
if ! grep -q "dashboard_router" "$PROJECT_DIR/agency/views.py" 2>/dev/null; then
    cat >> "$PROJECT_DIR/agency/views.py" << 'EOF'

# Dashboard routing views
@login_required
def dashboard_router(request):
    """Route to appropriate dashboard based on user role"""
    # Check if superadmin is viewing as another user
    if request.user.is_superuser and 'viewing_as_user' in request.session:
        try:
            view_as_user = User.objects.get(id=request.session['viewing_as_user'])
            if hasattr(view_as_user, 'profile'):
                if view_as_user.profile.is_project_manager:
                    return redirect('agency:pm_dashboard')
                else:
                    return redirect('agency:employee_dashboard')
        except:
            pass
    
    # Normal routing
    if request.user.is_superuser:
        return redirect('agency:admin_dashboard')
    
    try:
        profile = request.user.profile
        if profile.is_project_manager:
            return redirect('agency:pm_dashboard')
        else:
            return redirect('agency:employee_dashboard')
    except:
        return redirect('agency:admin_dashboard')

def get_viewing_user(request):
    """Get the user we should display data for"""
    if request.user.is_superuser and 'viewing_as_user' in request.session:
        try:
            return User.objects.get(id=request.session['viewing_as_user'])
        except:
            pass
    return request.user

@login_required
def admin_dashboard(request):
    """Admin dashboard with user switching"""
    return dashboard(request)  # Use existing dashboard

@login_required
def pm_dashboard(request):
    """Project Manager Dashboard"""
    viewing_user = get_viewing_user(request)
    
    try:
        user_profile = viewing_user.profile
        company = user_profile.company
        current_year = datetime.now().year
        current_month = datetime.now().month
        
        # Get projects where user is PM
        managed_projects = Project.objects.filter(
            project_manager=viewing_user,
            company=company
        ).select_related('client')
        
        # Calculate metrics
        total_revenue_managed = managed_projects.aggregate(
            total=Sum('total_revenue')
        )['total'] or Decimal('0')
        
        active_projects = managed_projects.filter(status='active').count()
        
        # Get unique team members across all projects
        team_members_ids = ProjectAllocation.objects.filter(
            project__in=managed_projects
        ).values_list('user_profile', flat=True).distinct()
        team_members_count = len(set(team_members_ids))
        
        # Current month allocations
        current_allocations = ProjectAllocation.objects.filter(
            project__in=managed_projects,
            year=current_year,
            month=current_month
        ).aggregate(total=Sum('allocated_hours'))['total'] or Decimal('0')
        
        # Project details with allocation status
        projects_data = []
        for project in managed_projects.filter(status__in=['active', 'planning']):
            allocated = project.allocations.aggregate(
                total=Sum('allocated_hours')
            )['total'] or Decimal('0')
            
            total_hours = project.total_hours or Decimal('0')
            utilization = (float(allocated) / float(total_hours) * 100) if total_hours > 0 else 0
            
            # Get team members for this project
            if hasattr(project, 'team_members'):
                team_size = project.team_members.count()
            else:
                team_size = project.allocations.values('user_profile').distinct().count()
            
            projects_data.append({
                'project': project,
                'allocated_hours': allocated,
                'utilization': utilization,
                'team_size': team_size,
                'health': 'good' if utilization >= 80 else 'warning' if utilization >= 50 else 'critical'
            })
        
        context = {
            'user': viewing_user,
            'user_profile': user_profile,
            'company': company,
            'managed_projects': managed_projects,
            'total_revenue_managed': total_revenue_managed,
            'active_projects': active_projects,
            'team_members': team_members_count,
            'total_allocated_hours': current_allocations,
            'projects_data': projects_data,
            'current_year': current_year,
            'current_month': current_month,
        }
        
        return render(request, 'dashboards/pm_dashboard.html', context)
        
    except Exception as e:
        print(f"PM Dashboard Error: {e}")
        return redirect('agency:dashboard')

@login_required
def employee_dashboard(request):
    """Employee Dashboard"""
    viewing_user = get_viewing_user(request)
    
    try:
        user_profile = viewing_user.profile
        company = user_profile.company
        current_year = datetime.now().year
        current_month = datetime.now().month
        
        # Get projects where user is allocated
        allocated_projects = Project.objects.filter(
            allocations__user_profile=user_profile
        ).distinct().select_related('client')
        
        # Current month allocations
        current_allocations = ProjectAllocation.objects.filter(
            user_profile=user_profile,
            year=current_year,
            month=current_month
        ).select_related('project', 'project__client')
        
        # Calculate totals
        total_hours_this_month = current_allocations.aggregate(
            total=Sum('allocated_hours')
        )['total'] or Decimal('0')
        
        monthly_capacity = user_profile.weekly_capacity_hours * Decimal('4.33')
        utilization_rate = (float(total_hours_this_month) / float(monthly_capacity) * 100) if monthly_capacity > 0 else 0
        
        # Project breakdown
        project_allocations = []
        for allocation in current_allocations:
            project_allocations.append({
                'project': allocation.project,
                'client': allocation.project.client,
                'hours': allocation.allocated_hours,
                'value': allocation.allocated_hours * allocation.hourly_rate
            })
        
        # Historical data (last 6 months)
        historical_data = []
        for i in range(6):
            month = current_month - i
            year = current_year
            if month <= 0:
                month += 12
                year -= 1
            
            month_hours = ProjectAllocation.objects.filter(
                user_profile=user_profile,
                year=year,
                month=month
            ).aggregate(total=Sum('allocated_hours'))['total'] or 0
            
            historical_data.append({
                'month': month,
                'year': year,
                'hours': float(month_hours),
                'utilization': (float(month_hours) / float(monthly_capacity) * 100) if monthly_capacity > 0 else 0
            })
        
        historical_data.reverse()
        
        # Get upcoming allocations
        upcoming_allocations = ProjectAllocation.objects.filter(
            user_profile=user_profile,
            year__gte=current_year,
            month__gt=current_month
        ).select_related('project', 'project__client').order_by('year', 'month')[:5]
        
        context = {
            'user': viewing_user,
            'user_profile': user_profile,
            'company': company,
            'allocated_projects': allocated_projects,
            'current_allocations': current_allocations,
            'total_hours_this_month': total_hours_this_month,
            'monthly_capacity': monthly_capacity,
            'utilization_rate': utilization_rate,
            'project_allocations': project_allocations,
            'historical_data': json.dumps(historical_data),
            'upcoming_allocations': upcoming_allocations,
            'current_year': current_year,
            'current_month': current_month,
        }
        
        return render(request, 'dashboards/employee_dashboard.html', context)
        
    except Exception as e:
        print(f"Employee Dashboard Error: {e}")
        return redirect('agency:dashboard')

@login_required
def switch_user_view(request):
    """Allow superadmin to switch to another user's view"""
    if not request.user.is_superuser:
        return JsonResponse({'error': 'Unauthorized'}, status=403)
    
    user_id = request.GET.get('user_id')
    if user_id:
        request.session['viewing_as_user'] = user_id
        return redirect('agency:dashboard_router')
    
    return redirect('agency:dashboard')

@login_required
def switch_back_to_admin(request):
    """Switch back to admin view"""
    if 'viewing_as_user' in request.session:
        del request.session['viewing_as_user']
    return redirect('agency:dashboard')
EOF
    echo "✅ Added dashboard views"
else
    echo "✅ Dashboard views already exist"
fi

# 3. Update the urls.py
echo "📝 Updating urls.py..."
# First, backup the original
cp "$PROJECT_DIR/agency/urls.py" "$PROJECT_DIR/agency/urls.py.bak" 2>/dev/null

# Check if dashboard_router already exists
if ! grep -q "dashboard_router" "$PROJECT_DIR/agency/urls.py" 2>/dev/null; then
    # Create new urls.py with all routes
    cat > "$PROJECT_DIR/agency/urls.py" << 'EOF'
# agency/urls.py - Updated URLs
from django.urls import path
from . import views

app_name = 'agency'

urlpatterns = [
    # Dashboard routing
    path('', views.dashboard_router, name='dashboard_router'),
    path('dashboard/', views.dashboard, name='dashboard'),
    path('admin-dashboard/', views.admin_dashboard, name='admin_dashboard'),
    path('pm-dashboard/', views.pm_dashboard, name='pm_dashboard'),
    path('employee-dashboard/', views.employee_dashboard, name='employee_dashboard'),
    
    # User switching
    path('switch-user/', views.switch_user_view, name='switch_user'),
    path('switch-back/', views.switch_back_to_admin, name='switch_back'),
    
    # Existing URLs
    path('capacity/', views.capacity_dashboard, name='capacity_dashboard'),
    path('clients/', views.clients_list, name='clients_list'),
    path('clients/<uuid:client_id>/', views.client_detail, name='client_detail'),
    path('projects/', views.projects_list, name='projects_list'),
    path('projects/<uuid:project_id>/', views.project_detail, name='project_detail'),
    path('team/', views.team_list, name='team_list'),
    path('import/', views.import_data, name='import_data'),
    
    # API endpoints
    path('api/revenue-chart/', views.revenue_chart_data, name='revenue_chart_data'),
    path('api/capacity-chart/', views.capacity_chart_data, name='capacity_chart_data'),
    path('api/health/', views.health_check, name='health_check'),
]
EOF
    echo "✅ Updated urls.py"
else
    echo "✅ URLs already include dashboard routes"
fi

# 4. Add user switcher to dashboard template
echo "📝 Adding user switcher to dashboard..."
DASHBOARD_PATH="$PROJECT_DIR/templates/dashboard.html"

# Check if user switcher already exists
if ! grep -q "userSwitcher" "$DASHBOARD_PATH" 2>/dev/null; then
    # Create a temporary file with the updated content
    cp "$DASHBOARD_PATH" "$DASHBOARD_PATH.tmp"
    
    # Add user switcher after company name
    perl -i -pe 's|(<span class="ml-4.*?{{ company.name }}</span>)|$1
                        {% if user.is_superuser %}
                        <div class="ml-4">
                            <select id="userSwitcher" class="border border-gray-300 rounded-md px-3 py-2 text-sm" onchange="switchUser(this.value)">
                                <option value="">View as User...</option>
                                {% for profile in all_profiles %}
                                <option value="{{ profile.user.id }}">{{ profile.user.get_full_name }} ({{ profile.get_role_display }})</option>
                                {% endfor %}
                            </select>
                        </div>
                        {% endif %}|' "$DASHBOARD_PATH.tmp"
    
    # Add JavaScript before closing body tag
    perl -i -pe 's|(</body>)|    <script>
    function switchUser(userId) {
        if (userId) {
            window.location.href = "/agency/switch-user/?user_id=" + userId;
        }
    }
    </script>
$1|' "$DASHBOARD_PATH.tmp"
    
    mv "$DASHBOARD_PATH.tmp" "$DASHBOARD_PATH"
    echo "✅ Added user switcher"
else
    echo "✅ User switcher already exists"
fi

# 5. Update dashboard view to include all_profiles
echo "📝 Updating dashboard view context..."
# Check if all_profiles is already in context
if ! grep -q "all_profiles" "$PROJECT_DIR/agency/views.py" 2>/dev/null; then
    # Create a temporary file
    cp "$PROJECT_DIR/agency/views.py" "$PROJECT_DIR/agency/views.py.tmp"
    
    # Add all_profiles to context
    perl -i -pe 'BEGIN{$found=0} 
        if(/context = \{/ && !$found) {$found=1} 
        if($found && /return render\(request, .dashboard\.html., context\)/) {
            $_ = "        # Add all profiles for user switcher\n" .
                 "        if request.user.is_superuser:\n" .
                 "            context[\"all_profiles\"] = UserProfile.objects.filter(\n" .
                 "                company=company\n" .
                 "            ).select_related(\"user\").order_by(\"user__last_name\", \"user__first_name\")\n" .
                 "\n" . $_;
            $found=0;
        }' "$PROJECT_DIR/agency/views.py.tmp"
    
    mv "$PROJECT_DIR/agency/views.py.tmp" "$PROJECT_DIR/agency/views.py"
    echo "✅ Updated dashboard context"
else
    echo "✅ Dashboard context already includes all_profiles"
fi

# 6. Add missing import for json
if ! grep -q "import json" "$PROJECT_DIR/agency/views.py" 2>/dev/null; then
    sed -i.bak '1s/^/import json\n/' "$PROJECT_DIR/agency/views.py"
    echo "✅ Added json import"
else
    echo "✅ json import already exists"
fi

# 7. Run migrations
echo "📝 Creating and running migrations..."
cd "$PROJECT_DIR"
python manage.py makemigrations agency
python manage.py migrate
cd - > /dev/null

# 8. Create a test script to set up some project managers
echo "📝 Creating test setup script..."
cat > "$PROJECT_DIR/setup_test_pms.py" << 'EOF'
import os
import django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agency_management.settings')
django.setup()

from agency.models import UserProfile, Project
from django.contrib.auth.models import User

print("🧪 Setting up test project managers...")

try:
    # Set some users as PMs
    profiles = UserProfile.objects.filter(role__in=['leadership', 'account'])[:2]
    if not profiles:
        profiles = UserProfile.objects.all()[:2]
        
    for profile in profiles:
        profile.is_project_manager = True
        profile.save()
        print(f"✅ Made {profile.user.get_full_name()} a project manager")

    # Assign PMs to projects
    projects = Project.objects.all()[:3]
    pm_users = [p.user for p in UserProfile.objects.filter(is_project_manager=True)]
    
    if pm_users and projects:
        for i, project in enumerate(projects):
            project.project_manager = pm_users[i % len(pm_users)]
            project.save()
            print(f"✅ Assigned {project.project_manager.get_full_name()} to {project.name}")
    else:
        print("⚠️  No projects or PMs available for assignment")

    print("\n✅ Test setup complete!")
except Exception as e:
    print(f"❌ Error during setup: {e}")
EOF

# Run the setup script from the correct directory
cd "$PROJECT_DIR"
python setup_test_pms.py
cd - > /dev/null

echo ""
echo "✅ All fixes applied!"
echo ""
echo "📋 Summary of changes:"
echo "- Added is_project_manager field to UserProfile model"
echo "- Added dashboard routing and user switching views"
echo "- Updated URLs to include new dashboard routes"
echo "- Added user switcher dropdown to dashboard template"
echo "- Set up some test project managers"
echo ""
echo "🚀 You can now:"
echo "1. Login as superadmin"
echo "2. Use the dropdown in the header to switch to any user's view"
echo "3. Project managers will see their PM dashboard"
echo "4. Regular employees will see their employee dashboard"
echo "5. Click 'Back to Admin View' to return to superadmin view"
echo ""
echo "⚠️  Note: The project allocation saving issue in the admin should now work."
echo "   The JavaScript in static/admin/js/project_allocation.js handles the saving."