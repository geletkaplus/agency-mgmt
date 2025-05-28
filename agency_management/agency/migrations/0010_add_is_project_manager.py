# Manual migration for is_project_manager field

from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        ('agency', '0009_merge_20250528_2047'),
    ]

    operations = [
        migrations.AddField(
            model_name='userprofile',
            name='is_project_manager',
            field=models.BooleanField(default=False, help_text='Can manage projects and see PM dashboard'),
        ),
    ]
