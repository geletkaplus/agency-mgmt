# agency/urls.py - Updated URLs
from django.urls import path
from . import views

app_name = 'agency'

urlpatterns = [
    path('', views.dashboard, name='dashboard'),
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
