from django.contrib import admin
from django.urls import path, include
from django.shortcuts import redirect

urlpatterns = [
    path('admin/', admin.site.urls),
    path('agency/', include('agency.urls')),
    path('', lambda request: redirect('agency:dashboard')),  # Redirect root to dashboard
]
