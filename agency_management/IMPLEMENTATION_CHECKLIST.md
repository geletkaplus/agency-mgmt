# Implementation Checklist

## 1. Database Field
- [ ] Run: python add_db_field.py
- [ ] Verify field exists: python manage.py shell
      >>> from agency.models import UserProfile
      >>> UserProfile._meta.get_field('is_project_manager')

## 2. Models.py
- [ ] Add to UserProfile class:
      is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")

## 3. Views.py
- [ ] Copy all functions from views_update.py to your views.py
- [ ] Import json at the top: import json

## 4. URLs.py
- [ ] Add URL patterns from urls_update.txt

## 5. Admin.py
- [ ] Replace save_allocations_view with the version from admin_allocation_fix.py
- [ ] Add datetime import at top: import datetime

## 6. Templates
- [ ] Create folder: templates/dashboards/
- [ ] Copy pm_dashboard.html and employee_dashboard.html from previous artifact
- [ ] Update dashboard.html with user switcher from dashboard_header_update.html

## 7. Static Files
- [ ] Make sure you have Chart.js loaded in your base template

## 8. Test
- [ ] Run: python test_dashboards.py
- [ ] Login as superadmin
- [ ] Test user switching dropdown
- [ ] Test PM dashboard shows managed projects
- [ ] Test employee dashboard shows allocations
- [ ] Test allocation saving in project admin

## 9. Assign Users
- [ ] In Django Admin > User Profiles:
      - Check "Is project manager" for PMs
- [ ] In Django Admin > Projects:
      - Assign Project Managers
      - Add team members
      - Test allocation grid
