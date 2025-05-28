import os

print("📝 Checking if is_project_manager field is in models.py...")

models_path = "agency/models.py"
with open(models_path, 'r') as f:
    content = f.read()

if 'is_project_manager' in content:
    print("✅ Field already in models.py")
else:
    print("❌ Field not found in models.py")
    print("   Adding it now...")
    
    # Find the UserProfile class and add the field
    lines = content.split('\n')
    new_lines = []
    in_userprofile = False
    field_added = False
    
    for i, line in enumerate(lines):
        new_lines.append(line)
        
        if 'class UserProfile' in line:
            in_userprofile = True
        
        if in_userprofile and not field_added and 'utilization_target' in line:
            # Add after utilization_target field
            new_lines.append('    is_project_manager = models.BooleanField(default=False, help_text="Can manage projects and see PM dashboard")')
            field_added = True
            print("✅ Added is_project_manager field after utilization_target")
    
    if field_added:
        with open(models_path, 'w') as f:
            f.write('\n'.join(new_lines))
        print("✅ models.py updated!")
    else:
        print("⚠️  Could not automatically add field. Please add manually:")
        print("    is_project_manager = models.BooleanField(default=False, help_text=\"Can manage projects and see PM dashboard\")")
