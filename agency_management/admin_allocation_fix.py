# Replace the save_allocations_view method in ProjectAdmin with this:

def save_allocations_view(self, request, object_id):
    """Handle allocation saves via AJAX - FIXED VERSION"""
    if request.method == 'POST':
        try:
            project = self.get_object(request, object_id)
            data = json.loads(request.body)
            allocations = data.get('allocations', [])
            
            # Log what we received
            print(f"Received {len(allocations)} allocation entries")
            
            # Clear existing allocations
            ProjectAllocation.objects.filter(project=project).delete()
            
            # Process allocations
            monthly_totals = {}
            for alloc in allocations:
                member_id = alloc.get('member_id') or alloc.get('user_profile')
                year = int(alloc.get('year', 0))
                month = int(alloc.get('month', 0))
                hours = float(alloc.get('hours', 0))
                
                if member_id and year and month and hours > 0:
                    key = (str(member_id), year, month)
                    if key not in monthly_totals:
                        monthly_totals[key] = 0
                    monthly_totals[key] += hours
            
            # Create allocations
            created_count = 0
            for (member_id, year, month), hours in monthly_totals.items():
                try:
                    member = UserProfile.objects.get(id=member_id)
                    ProjectAllocation.objects.create(
                        project=project,
                        user_profile=member,
                        year=year,
                        month=month,
                        allocated_hours=Decimal(str(hours)),
                        hourly_rate=member.hourly_rate
                    )
                    created_count += 1
                except Exception as e:
                    print(f"Error creating allocation: {e}")
            
            return JsonResponse({
                'status': 'success',
                'message': f'Created {created_count} allocations'
            })
            
        except Exception as e:
            import traceback
            print(f"Allocation save error: {e}")
            print(traceback.format_exc())
            return JsonResponse({
                'status': 'error',
                'message': str(e)
            }, status=500)
    
    return JsonResponse({
        'status': 'error',
        'message': 'Invalid request method'
    }, status=400)
