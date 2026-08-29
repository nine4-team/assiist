// Assiist Admin Portal - JavaScript API Integration

class AdminAPI {
    constructor() {
        this.baseUrl = '/admin/api';
        this.headers = {
            'Content-Type': 'application/json'
        };
        this.requestTimeout = 30000; // 30 seconds
    }

    // Generic API request handler with error handling
    async request(endpoint, options = {}) {
        let url = `${this.baseUrl}${endpoint}`;
        
        // Handle query parameters
        if (options.params) {
            const queryParams = new URLSearchParams();
            for (const [key, value] of Object.entries(options.params)) {
                if (value) {  // Only add non-empty values
                    queryParams.append(key, value);
                }
            }
            const queryString = queryParams.toString();
            if (queryString) {
                url += `?${queryString}`;
            }
            delete options.params;  // Remove params from options to avoid confusion
        }
        
        const defaultOptions = {
            headers: this.headers,
            timeout: this.requestTimeout,
            ...options
        };

        try {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), this.requestTimeout);
            
            const response = await fetch(url, {
                ...defaultOptions,
                signal: controller.signal
            });
            
            clearTimeout(timeoutId);
            
            if (!response.ok) {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`);
            }
            
            return await response.json();
        } catch (error) {
            if (error.name === 'AbortError') {
                throw new Error('Request timeout - please try again');
            }
            throw error;
        }
    }

    // Account operations
    async createAccountOnly(accountData) {
        return await this.request('/accounts', {
            method: 'POST',
            body: JSON.stringify(accountData)
        });
    }

    async createAccountWithOwner(accountData, ownerData) {
        return await this.request('/accounts/with-owner', {
            method: 'POST',
            body: JSON.stringify({
                account_data: accountData,
                owner_data: ownerData
            })
        });
    }

    async getAllAccounts() {
        return await this.request('/accounts');
    }

    async getAccountById(accountId) {
        return await this.request(`/accounts/${accountId}`);
    }

    // User operations
    async createUser(userData) {
        return await this.request('/users', {
            method: 'POST',
            body: JSON.stringify(userData)
        });
    }

    async getAllUsers() {
        return await this.request('/users');
    }

    // Delete operations (soft delete)
    async deleteAccount(accountId, deleterUserId) {
        return await this.request(`/accounts/${accountId}`, {
            method: 'DELETE',
            body: JSON.stringify({
                deleter_user_id: deleterUserId
            })
        });
    }

    async deleteUser(userId, deleterUserId) {
        return await this.request(`/users/${userId}`, {
            method: 'DELETE',
            body: JSON.stringify({
                deleter_user_id: deleterUserId
            })
        });
    }

    // GenAI request operations
    async getGenAIRequests(filters = {}) {
        return await this.request('/genai-requests', {
            params: filters
        });
    }

    async getGenAIRequestById(requestId) {
        return await this.request(`/genai-requests/${requestId}`);
    }
}

// Initialize API client
const adminAPI = new AdminAPI();

// Form handling utilities
class FormHandler {
    constructor(formId, submitCallback, options = {}) {
        this.form = document.getElementById(formId);
        this.submitCallback = submitCallback;
        this.options = {
            showLoading: true,
            resetOnSuccess: true,
            validateOnSubmit: true,
            ...options
        };
        
        if (this.form) {
            this.init();
        }
    }

    init() {
        this.form.addEventListener('submit', this.handleSubmit.bind(this));
        
        // Add real-time validation
        if (this.options.validateOnSubmit) {
            this.addValidation();
        }
    }

    async handleSubmit(e) {
        e.preventDefault();
        
        if (this.options.validateOnSubmit && !this.validateForm()) {
            return;
        }

        const formData = new FormData(this.form);
        const data = Object.fromEntries(formData.entries());
        
        // Remove empty values
        Object.keys(data).forEach(key => {
            if (data[key] === '' || data[key] === null) {
                delete data[key];
            }
        });

        try {
            if (this.options.showLoading) {
                this.showFormLoading();
            }
            
            await this.submitCallback(data);
            
            if (this.options.resetOnSuccess) {
                this.form.reset();
                this.clearValidation();
            }
            
        } catch (error) {
            console.error('Form submission error:', error);
            showError(error.message || 'An error occurred. Please try again.');
        } finally {
            if (this.options.showLoading) {
                this.hideFormLoading();
            }
        }
    }

    validateForm() {
        let isValid = true;
        const inputs = this.form.querySelectorAll('input[required], select[required], textarea[required]');
        
        inputs.forEach(input => {
            if (!this.validateInput(input)) {
                isValid = false;
            }
        });
        
        return isValid;
    }

    validateInput(input) {
        const value = input.value.trim();
        let isValid = true;
        let errorMessage = '';

        // Required validation
        if (input.hasAttribute('required') && !value) {
            isValid = false;
            errorMessage = 'This field is required';
        }

        // Email validation
        if (input.type === 'email' && value) {
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(value)) {
                isValid = false;
                errorMessage = 'Please enter a valid email address';
            }
        }

        // Display validation result
        this.showValidation(input, isValid, errorMessage);
        return isValid;
    }

    showValidation(input, isValid, message) {
        // Remove existing validation classes
        input.classList.remove('is-valid', 'is-invalid');
        
        // Remove existing feedback
        const existingFeedback = input.parentNode.querySelector('.invalid-feedback, .valid-feedback');
        if (existingFeedback) {
            existingFeedback.remove();
        }

        if (!isValid && message) {
            input.classList.add('is-invalid');
            const feedback = document.createElement('div');
            feedback.className = 'invalid-feedback';
            feedback.textContent = message;
            input.parentNode.appendChild(feedback);
        } else if (input.value.trim()) {
            input.classList.add('is-valid');
        }
    }

    clearValidation() {
        const inputs = this.form.querySelectorAll('input, select, textarea');
        inputs.forEach(input => {
            input.classList.remove('is-valid', 'is-invalid');
        });
        
        const feedbacks = this.form.querySelectorAll('.invalid-feedback, .valid-feedback');
        feedbacks.forEach(feedback => feedback.remove());
    }

    addValidation() {
        const inputs = this.form.querySelectorAll('input, select, textarea');
        inputs.forEach(input => {
            input.addEventListener('blur', () => this.validateInput(input));
            input.addEventListener('input', () => {
                if (input.classList.contains('is-invalid')) {
                    this.validateInput(input);
                }
            });
        });
    }

    showFormLoading() {
        const submitBtn = this.form.querySelector('button[type="submit"]');
        if (submitBtn) {
            submitBtn.disabled = true;
            const originalText = submitBtn.innerHTML;
            submitBtn.setAttribute('data-original-text', originalText);
            submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>Processing...';
        }
    }

    hideFormLoading() {
        const submitBtn = this.form.querySelector('button[type="submit"]');
        if (submitBtn) {
            submitBtn.disabled = false;
            const originalText = submitBtn.getAttribute('data-original-text');
            if (originalText) {
                submitBtn.innerHTML = originalText;
            }
        }
    }
}

// Data table utilities
class DataTable {
    constructor(containerId, options = {}) {
        this.container = document.getElementById(containerId);
        this.options = {
            searchable: true,
            sortable: true,
            paginated: false,
            generateActionButtons: null,  // Custom function to generate action buttons
            ...options
        };
        this.data = [];
        this.filteredData = [];
        this.sortColumn = null;
        this.sortDirection = 'asc';
    }

    setData(data) {
        this.data = data;
        this.filteredData = [...data];
        this.render();
    }

    render() {
        if (!this.container) return;

        const tableHtml = this.generateTableHtml();
        this.container.innerHTML = tableHtml;
        
        if (this.options.searchable) {
            this.addSearchFunctionality();
        }
        
        if (this.options.sortable) {
            this.addSortFunctionality();
        }
    }

    generateTableHtml() {
        if (this.filteredData.length === 0) {
            return `
                <div class="text-center p-4">
                    <i class="fas fa-inbox fa-3x text-muted mb-3"></i>
                    <h5 class="text-muted">No data found</h5>
                    <p class="text-muted">There are no records to display.</p>
                </div>
            `;
        }

        return `
            <div class="table-responsive">
                <table class="table table-hover">
                    <thead class="table-dark">
                        ${this.generateHeaderHtml()}
                    </thead>
                    <tbody>
                        ${this.generateBodyHtml()}
                    </tbody>
                </table>
            </div>
        `;
    }

    generateHeaderHtml() {
        if (this.filteredData.length === 0) return '';
        
        const firstRow = this.filteredData[0];
        const headers = Object.keys(firstRow).map(key => {
            const displayName = this.formatColumnName(key);
            const sortIcon = this.getSortIcon(key);
            return `
                <th class="sortable" data-column="${key}">
                    ${displayName} ${sortIcon}
                </th>
            `;
        }).join('');
        
        return `<tr>${headers}<th>Actions</th></tr>`;
    }

    generateBodyHtml() {
        return this.filteredData.map(row => {
            const cells = Object.entries(row).map(([key, value]) => {
                const formattedValue = this.formatCellValue(key, value);
                return `<td>${formattedValue}</td>`;
            }).join('');
            
            const actions = this.generateActionButtons(row);
            return `<tr>${cells}<td>${actions}</td></tr>`;
        }).join('');
    }

    formatColumnName(key) {
        return key.split('_').map(word => 
            word.charAt(0).toUpperCase() + word.slice(1)
        ).join(' ');
    }

    formatCellValue(key, value) {
        if (value === null || value === undefined) {
            return '<span class="text-muted">N/A</span>';
        }
        
        if (key.includes('_on') || key.includes('_at')) {
            return formatDateTime(value);
        }
        
        if (key === 'id') {
            return `
                <code class="small">${value}</code>
                <button class="btn btn-sm btn-outline-secondary ms-1" 
                        onclick="copyToClipboard('${value}')" title="Copy ID">
                    <i class="fas fa-copy"></i>
                </button>
            `;
        }
        
        return String(value);
    }

    generateActionButtons(row) {
        if (this.options.generateActionButtons) {
            return this.options.generateActionButtons(row);
        }
        
        // Default action buttons if no custom generator provided
        return `
            <div class="btn-group" role="group">
                <button type="button" class="btn btn-sm btn-outline-primary" 
                        onclick="viewDetails('${row.id}')" title="View Details">
                    <i class="fas fa-eye"></i>
                </button>
                <button type="button" class="btn btn-sm btn-outline-info" 
                        onclick="editRecord('${row.id}')" title="Edit">
                    <i class="fas fa-edit"></i>
                </button>
            </div>
        `;
    }

    getSortIcon(column) {
        if (this.sortColumn !== column) {
            return '<i class="fas fa-sort text-muted ms-1"></i>';
        }
        
        const icon = this.sortDirection === 'asc' ? 'fa-sort-up' : 'fa-sort-down';
        return `<i class="fas ${icon} text-primary ms-1"></i>`;
    }

    addSearchFunctionality() {
        const searchInput = document.getElementById('searchInput');
        if (searchInput) {
            searchInput.addEventListener('input', (e) => {
                this.search(e.target.value);
            });
        }
    }

    addSortFunctionality() {
        const headers = this.container.querySelectorAll('th.sortable');
        headers.forEach(header => {
            header.addEventListener('click', () => {
                const column = header.getAttribute('data-column');
                this.sort(column);
            });
        });
    }

    search(searchTerm) {
        const term = searchTerm.toLowerCase().trim();
        
        if (!term) {
            this.filteredData = [...this.data];
        } else {
            this.filteredData = this.data.filter(row => {
                return Object.values(row).some(value => {
                    return String(value).toLowerCase().includes(term);
                });
            });
        }
        
        this.render();
    }

    sort(column) {
        if (this.sortColumn === column) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortColumn = column;
            this.sortDirection = 'asc';
        }

        this.filteredData.sort((a, b) => {
            const aVal = a[column];
            const bVal = b[column];
            
            if (aVal === null || aVal === undefined) return 1;
            if (bVal === null || bVal === undefined) return -1;
            
            let comparison = 0;
            if (typeof aVal === 'string' && typeof bVal === 'string') {
                comparison = aVal.localeCompare(bVal);
            } else {
                comparison = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
            }
            
            return this.sortDirection === 'asc' ? comparison : -comparison;
        });

        this.render();
    }
}

// Utility functions
function formatDateTime(dateString) {
    if (!dateString) return 'N/A';
    try {
        const date = new Date(dateString);
        return date.toLocaleString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    } catch (error) {
        return 'Invalid Date';
    }
}

function copyToClipboard(text) {
    if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(() => {
            showSuccess('Copied to clipboard!');
        }).catch(() => {
            fallbackCopyToClipboard(text);
        });
    } else {
        fallbackCopyToClipboard(text);
    }
}

function fallbackCopyToClipboard(text) {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    textArea.style.position = 'fixed';
    textArea.style.left = '-999999px';
    textArea.style.top = '-999999px';
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    
    try {
        document.execCommand('copy');
        showSuccess('Copied to clipboard!');
    } catch (err) {
        showError('Failed to copy to clipboard');
    }
    
    document.body.removeChild(textArea);
}

// Global notification functions
function showLoading(title = 'Loading', subtitle = 'Please wait...') {
    const modal = document.getElementById('loadingModal');
    if (modal) {
        document.getElementById('loadingMessage').textContent = title;
        document.getElementById('loadingSubtext').textContent = subtitle;
        new bootstrap.Modal(modal).show();
    }
}

function hideLoading() {
    const modal = document.getElementById('loadingModal');
    if (modal) {
        const bsModal = bootstrap.Modal.getInstance(modal);
        if (bsModal) bsModal.hide();
    }
}

function showSuccess(message) {
    const toast = document.getElementById('successToast');
    if (toast) {
        document.getElementById('successMessage').textContent = message;
        new bootstrap.Toast(toast, { delay: 4000 }).show();
    }
}

function showError(message) {
    const toast = document.getElementById('errorToast');
    if (toast) {
        document.getElementById('errorMessage').textContent = message;
        new bootstrap.Toast(toast, { delay: 6000 }).show();
    }
}

// Animation utilities
function animateIn(element, animation = 'fadeInUp') {
    element.classList.add(animation);
    element.addEventListener('animationend', () => {
        element.classList.remove(animation);
    }, { once: true });
}

function animateOut(element, animation = 'fadeOut') {
    element.classList.add(animation);
    return new Promise(resolve => {
        element.addEventListener('animationend', () => {
            element.classList.remove(animation);
            resolve();
        }, { once: true });
    });
}

// Page-specific functionality will be added by individual pages
const pageHandlers = {};

// Export for global access
window.AdminAPI = AdminAPI;
window.FormHandler = FormHandler;
window.DataTable = DataTable;
window.adminAPI = adminAPI;
window.pageHandlers = pageHandlers;

// Initialize common functionality
document.addEventListener('DOMContentLoaded', function() {
    // Add loading states to all buttons
    const buttons = document.querySelectorAll('.btn[data-loading]');
    buttons.forEach(button => {
        button.addEventListener('click', function() {
            if (!this.disabled) {
                this.classList.add('loading');
                setTimeout(() => {
                    this.classList.remove('loading');
                }, 2000);
            }
        });
    });

    // Add hover effects to cards
    const cards = document.querySelectorAll('.card');
    cards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-4px)';
        });
        
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0)';
        });
    });

    // Initialize tooltips
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
});

// Delete functionality
async function confirmDeleteAccount(accountId, accountName) {
    const confirmed = confirm(
        `Are you sure you want to delete the account "${accountName}"?\n\n` +
        `This will mark the account as deleted (soft delete) but can be recovered if needed.\n\n` +
        `Account ID: ${accountId}`
    );
    
    if (!confirmed) return;
    
    try {
        showLoading('Deleting Account', 'Please wait while we mark the account as deleted...');
        
        // Use a default admin user ID for deletion tracking
        // In a real implementation, this would come from the current admin user's session
        const deleterUserId = 'admin-portal-user';
        
        await adminAPI.deleteAccount(accountId, deleterUserId);
        
        hideLoading();
        showSuccess(`Account "${accountName}" has been marked as deleted successfully.`);
        
        // Reload the accounts list
        if (typeof loadAccounts === 'function') {
            loadAccounts();
        } else if (typeof window.loadAccounts === 'function') {
            window.loadAccounts();
        }
        
    } catch (error) {
        hideLoading();
        console.error('Delete account error:', error);
        showError(`Failed to delete account: ${error.message}`);
    }
}

async function confirmDeleteUser(userId, userName, userEmail) {
    const confirmed = confirm(
        `Are you sure you want to delete the user "${userName}" (${userEmail})?\n\n` +
        `This will mark the user as deleted (soft delete) but can be recovered if needed.\n\n` +
        `User ID: ${userId}`
    );
    
    if (!confirmed) return;
    
    try {
        showLoading('Deleting User', 'Please wait while we mark the user as deleted...');
        
        // Use a default admin user ID for deletion tracking
        // In a real implementation, this would come from the current admin user's session
        const deleterUserId = 'admin-portal-user';
        
        await adminAPI.deleteUser(userId, deleterUserId);
        
        hideLoading();
        showSuccess(`User "${userName}" has been marked as deleted successfully.`);
        
        // Reload the users list
        if (typeof loadUsers === 'function') {
            loadUsers();
        } else if (typeof window.loadUsers === 'function') {
            window.loadUsers();
        }
        
    } catch (error) {
        hideLoading();
        console.error('Delete user error:', error);
        showError(`Failed to delete user: ${error.message}`);
    }
}

// Make functions globally available
window.confirmDeleteAccount = confirmDeleteAccount;
window.confirmDeleteUser = confirmDeleteUser;

// API instance and classes are available globally via window object 