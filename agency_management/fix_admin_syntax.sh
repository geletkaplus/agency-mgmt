#!/bin/bash

# Fix the syntax error in admin.py

echo "Fixing syntax error in admin.py..."

# Create a Python script to fix the issue
cat > fix_admin_syntax.py << 'PYTHON_FIX'
import re

try:
    # Read the admin.py file
    with open('agency/admin.py', 'r') as f:
        content = f.read()
    
    # Fix the escaped quotes in the ordering line
    # Replace the malformed line with the correct one
    content = content.replace(
        "ordering = [\\'-year\\', \\'-month\\', \\'project__name\\']",
        "ordering = ['-year', '-month', 'project__name']"
    )
    
    # Also check for any other escaped quotes that might have been added
    content = content.replace("\\'", "'")
    
    # Write the fixed content back
    with open('agency/admin.py', 'w') as f:
        f.write(content)
    
    print("✓ Fixed syntax error in admin.py")
    
    # Show the fixed line for confirmation
    with open('agency/admin.py', 'r') as f:
        lines = f.readlines()
        for i, line in enumerate(lines):
            if 'ordering = [' in line and 'year' in line:
                print(f"Line {i+1}: {line.strip()}")
                
except Exception as e:
    print(f"Error fixing admin.py: {e}")
PYTHON_FIX

# Run the fix
python fix_admin_syntax.py

# Remove the temporary file
rm fix_admin_syntax.py

echo "Done! You can now run the server again."