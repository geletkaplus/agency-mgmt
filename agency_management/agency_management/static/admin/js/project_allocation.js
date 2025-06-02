// Project allocation grid JavaScript
console.log('Project allocation script loaded');

document.addEventListener('DOMContentLoaded', function() {
    // Add any custom JavaScript for the allocation grid here
    const allocationInputs = document.querySelectorAll('.allocation-input');
    
    allocationInputs.forEach(input => {
        input.addEventListener('change', function() {
            // You can add validation or auto-save functionality here
            console.log('Allocation changed:', this.value);
        });
    });
});
