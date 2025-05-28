# Agency Management Dashboard Updates

## Changes Made:

1. **Added is_project_manager field to UserProfile model**
   - Run migration: `python manage.py migrate`

2. **Created new dashboard views:**
   - PM Dashboard: Shows projects under management, team allocations, revenue managed
   - Employee Dashboard: Shows personal allocations, utilization, upcoming work
   - Dashboard Router: Automatically routes users to appropriate dashboard

3. **Added user switching for superadmins:**
   - Dropdown in header to switch to any user's view
   - "Back to Admin View" button when viewing as another user

4. **Fixed allocation save issue:**
   - Updated save_allocations_view to properly handle the data format
   - Better error handling and debugging

5. **Added PM checkbox to allocation grid:**
   - Checkbox next to each team member to assign as PM
   - Automatically updates project manager when checked

## Manual Updates Required:

### 1. Update agency/models.py
Add to UserProfile class:
```python
is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")
```

### 2. Update agency/views.py
- Add the new dashboard views from views_dashboards.py
- Add dashboard_router function
- Update the main dashboard view to include all_profiles in context for superusers

### 3. Update agency/urls.py
Add these URL patterns:
```python
path('', views.dashboard_router, name='dashboard_router'),
path('admin-dashboard/', views.dashboard, name='dashboard'),
path('pm-dashboard/', views.pm_dashboard, name='pm_dashboard'),
path('employee-dashboard/', views.employee_dashboard, name='employee_dashboard'),
path('switch-user/', views.switch_user_view, name='switch_user'),
path('switch-back/', views.switch_back_to_admin, name='switch_back'),
```

### 4. Update agency/admin.py
- Replace save_allocations_view with the fixed version
- Add update-pm URL and view for updating project manager

### 5. Update templates/dashboard.html
Add the user switcher dropdown for superadmins (see dashboard_update.html)

### 6. Create new templates
- templates/dashboards/pm_dashboard.html
- templates/dashboards/employee_dashboard.html

### 7. Update static files
Update project_allocation.js with PM checkbox functionality

## Testing:

1. Run migrations: `python manage.py migrate`
2. Mark some users as project managers in admin
3. Assign project managers to projects
4. Test allocation saving
5. Test user switching as superadmin
6. Test PM and employee dashboards

## Setting Up Users:

1. In Django Admin, go to User Profiles
2. Check "Is project manager" for users who should have PM access
3. Assign PMs to projects in the Project admin
4. Team members will see their allocations in employee dashboard
5. PMs will see all their managed projects in PM dashboard
