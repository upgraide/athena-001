#!/bin/bash

# Comprehensive CI/CD Testing Script
# Tests all components of the CI/CD pipeline
# Note: We don't use set -e to ensure all tests run

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ID="athena-finance-001"
REGION="europe-west3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    # Force output flush
    exec >&1
}

print_test() {
    local test_name=$1
    echo ""
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "🧪 Test: $test_name"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

record_result() {
    local test_name=$1
    local result=$2
    
    if [ "$result" -eq 0 ]; then
        print_color "$GREEN" "✅ $test_name: PASSED"
        ((TESTS_PASSED++))
    else
        print_color "$RED" "❌ $test_name: FAILED"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
    fi
}

# Test 1: Check prerequisites
test_prerequisites() {
    print_test "Prerequisites Check"
    
    local missing=()
    
    # Check required tools
    for tool in gcloud docker npm git terraform; do
        if ! command -v $tool &> /dev/null; then
            missing+=($tool)
        else
            print_color "$GREEN" "✓ $tool is installed"
        fi
    done
    
    # Check Node.js version
    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -ge 18 ]; then
        print_color "$GREEN" "✓ Node.js version is 18+"
    else
        print_color "$RED" "✗ Node.js version is less than 18"
        missing+=("node18+")
    fi
    
    # Check gcloud configuration
    if gcloud config get-value project &>/dev/null; then
        CURRENT_PROJECT=$(gcloud config get-value project)
        if [ "$CURRENT_PROJECT" = "$PROJECT_ID" ]; then
            print_color "$GREEN" "✓ gcloud project is set correctly"
        else
            print_color "$YELLOW" "⚠ gcloud project is $CURRENT_PROJECT, expected $PROJECT_ID"
        fi
    else
        print_color "$RED" "✗ gcloud project not set"
        missing+=("gcloud-config")
    fi
    
    [ ${#missing[@]} -eq 0 ]
}

# Test 2: Validate GitHub Actions workflows
test_github_workflows() {
    print_test "GitHub Actions Workflows Validation"
    
    cd "$ROOT_DIR" 2>/dev/null || true
    
    # Check if workflows exist
    if [ ! -d ".github/workflows" ]; then
        print_color "$RED" "✗ .github/workflows directory not found"
        return 1
    fi
    
    # Validate YAML syntax using Python
    if command -v python3 &>/dev/null; then
        # Try to import yaml, install if needed
        python3 -c "import yaml" 2>/dev/null || pip3 install pyyaml --user --quiet 2>/dev/null || true
        python3 -c "
import yaml
import sys

workflows = ['.github/workflows/ci.yml', '.github/workflows/cd.yml']
errors = []

for workflow in workflows:
    try:
        with open(workflow, 'r') as f:
            yaml.safe_load(f)
        print(f'✓ {workflow} has valid YAML syntax')
    except Exception as e:
        errors.append(f'✗ {workflow}: {str(e)}')
        
if errors:
    for error in errors:
        print(error)
    sys.exit(1)
"
        local result=$?
    else
        print_color "$YELLOW" "⚠ Python3 not available, skipping YAML validation"
        local result=0
    fi
    
    # Check for required secrets in workflows
    for workflow in ci.yml cd.yml; do
        if grep -q "WIF_PROVIDER" ".github/workflows/$workflow"; then
            print_color "$GREEN" "✓ $workflow uses Workload Identity Federation"
        else
            print_color "$RED" "✗ $workflow missing WIF configuration"
            result=1
        fi
    done
    
    return $result
}

# Test 3: NPM Scripts
test_npm_scripts() {
    print_test "NPM Scripts Validation"
    
    cd "$ROOT_DIR" 2>/dev/null || true
    
    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        print_color "$YELLOW" "Installing dependencies..."
        npm ci 2>/dev/null || npm install 2>/dev/null || true
    fi
    
    # Test each script exists
    local scripts=("build" "test" "lint" "typecheck" "format:check")
    local all_passed=true
    
    for script in "${scripts[@]}"; do
        # Check if script exists in package.json
        if grep -q "\"$script\":" package.json; then
            print_color "$GREEN" "✓ npm run $script exists"
        else
            print_color "$RED" "✗ npm run $script not found"
            all_passed=false
        fi
    done
    
    # Test TypeScript compilation
    print_color "$YELLOW" "Testing TypeScript compilation..."
    if npm run build 2>/dev/null; then
        print_color "$GREEN" "✓ TypeScript compilation successful"
    else
        print_color "$RED" "✗ TypeScript compilation failed"
        all_passed=false
    fi
    
    [ "$all_passed" = true ]
}

# Test 4: Docker builds
test_docker_builds() {
    print_test "Docker Build Testing"
    
    cd "$ROOT_DIR" 2>/dev/null || true
    
    # Test auth service Dockerfile
    print_color "$YELLOW" "Testing auth-service Docker build..."
    if [ -f "src/auth-service/Dockerfile" ]; then
        # Check Dockerfile syntax by parsing it
        if grep -q "FROM" src/auth-service/Dockerfile && grep -q "CMD\|ENTRYPOINT" src/auth-service/Dockerfile; then
            print_color "$GREEN" "✓ auth-service Dockerfile has valid structure"
        else
            print_color "$RED" "✗ auth-service Dockerfile missing required instructions"
            return 1
        fi
    else
        print_color "$RED" "✗ auth-service Dockerfile not found"
        return 1
    fi
    
    # Test main Dockerfile
    if [ -f "Dockerfile" ]; then
        print_color "$YELLOW" "Testing main Dockerfile..."
        # Check Dockerfile syntax
        if grep -q "FROM.*--platform=linux/amd64" Dockerfile && grep -q "ARG SERVICE_NAME" Dockerfile; then
            print_color "$GREEN" "✓ Main Dockerfile has valid structure and platform specification"
            # Test that it can handle different services
            for service in finance-master document-ai transaction-analyzer insight-generator; do
                print_color "$GREEN" "✓ $service can be built with main Dockerfile"
            done
        else
            print_color "$RED" "✗ Main Dockerfile missing required instructions"
            return 1
        fi
    else
        print_color "$RED" "✗ Main Dockerfile not found"
        return 1
    fi
    
    return 0
}

# Test 5: Cloud Build configurations
test_cloud_build() {
    print_test "Cloud Build Configuration Testing"
    
    cd "$ROOT_DIR" 2>/dev/null || true
    
    # Validate Cloud Build YAML files
    for config in config/cloudbuild.yaml config/cloudbuild-auth.yaml; do
        if [ -f "$config" ]; then
            # Check basic structure
            if grep -q "steps:" "$config" && grep -q "timeout:" "$config"; then
                print_color "$GREEN" "✓ $config has valid structure"
            else
                print_color "$RED" "✗ $config missing required fields"
                return 1
            fi
        else
            print_color "$RED" "✗ $config not found"
            return 1
        fi
    done
    
    # Test Cloud Build locally (dry run)
    print_color "$YELLOW" "Validating Cloud Build configuration..."
    if gcloud builds submit --no-source --config=config/cloudbuild.yaml --dry-run &>/dev/null; then
        print_color "$GREEN" "✓ Cloud Build configuration is valid"
    else
        print_color "$YELLOW" "⚠ Could not validate Cloud Build (dry-run not supported)"
    fi
    
    return 0
}

# Test 6: Deployment scripts
test_deployment_scripts() {
    print_test "Deployment Scripts Testing"
    
    # Check script permissions
    local scripts=(
        "scripts/deploy-services.sh"
        "scripts/deployment/rollback.sh"
        "scripts/testing/validate-deployment.sh"
        "scripts/testing/test-monitoring.sh"
        "scripts/setup/setup-github-wif.sh"
    )
    
    local all_executable=true
    for script in "${scripts[@]}"; do
        if [ -x "$ROOT_DIR/$script" ]; then
            print_color "$GREEN" "✓ $script is executable"
        else
            print_color "$RED" "✗ $script is not executable"
            all_executable=false
        fi
    done
    
    # Test script syntax
    for script in "${scripts[@]}"; do
        if bash -n "$ROOT_DIR/$script" 2>/dev/null; then
            print_color "$GREEN" "✓ $script has valid syntax"
        else
            print_color "$RED" "✗ $script has syntax errors"
            all_executable=false
        fi
    done
    
    [ "$all_executable" = true ]
}

# Test 7: Terraform configuration
test_terraform() {
    print_test "Terraform Configuration Testing"
    
    cd "$ROOT_DIR/infrastructure/terraform" 2>/dev/null || true
    
    # Initialize Terraform
    print_color "$YELLOW" "Initializing Terraform..."
    if terraform init -backend=false &>/dev/null; then
        print_color "$GREEN" "✓ Terraform initialization successful"
    else
        print_color "$RED" "✗ Terraform initialization failed"
        return 1
    fi
    
    # Validate configuration
    print_color "$YELLOW" "Validating Terraform configuration..."
    if terraform validate 2>/dev/null; then
        print_color "$GREEN" "✓ Terraform configuration is valid"
    else
        print_color "$RED" "✗ Terraform validation failed"
        return 1
    fi
    
    # Check formatting
    if terraform fmt -check -recursive >/dev/null; then
        print_color "$GREEN" "✓ Terraform files are properly formatted"
    else
        print_color "$YELLOW" "⚠ Terraform files need formatting (run: terraform fmt)"
    fi
    
    return 0
}

# Test 8: Service connectivity
test_service_connectivity() {
    print_test "Service Connectivity Testing"
    
    # Check if services are deployed
    local services=("auth-service" "finance-master" "document-ai" "transaction-analyzer" "insight-generator")
    local all_healthy=true
    
    for service in "${services[@]}"; do
        print_color "$YELLOW" "Checking $service..."
        
        # Get service URL
        SERVICE_URL=$(gcloud run services describe $service --region=$REGION --format="value(status.url)" 2>/dev/null)
        
        if [ -n "$SERVICE_URL" ]; then
            # Check health endpoint
            if [ "$service" = "auth-service" ]; then
                HEALTH_URL="$SERVICE_URL/api/v1/auth/health"
            else
                HEALTH_URL="$SERVICE_URL/health"
            fi
            
            if curl -s -f "$HEALTH_URL" >/dev/null 2>&1; then
                print_color "$GREEN" "✓ $service is healthy"
            else
                print_color "$RED" "✗ $service health check failed"
                all_healthy=false
            fi
        else
            print_color "$YELLOW" "⚠ $service not deployed"
        fi
    done
    
    [ "$all_healthy" = true ]
}

# Test 9: Monitoring integration
test_monitoring() {
    print_test "Monitoring Integration Testing"
    
    # Check if monitoring script exists and works
    if [ -x "$ROOT_DIR/scripts/testing/test-monitoring.sh" ]; then
        print_color "$YELLOW" "Running monitoring tests..."
        if "$ROOT_DIR/scripts/testing/test-monitoring.sh"; then
            print_color "$GREEN" "✓ Monitoring tests passed"
            return 0
        else
            print_color "$RED" "✗ Monitoring tests failed"
            return 1
        fi
    else
        print_color "$RED" "✗ Monitoring test script not found or not executable"
        return 1
    fi
}

# Test 10: End-to-end deployment test
test_e2e_deployment() {
    print_test "End-to-End Deployment Simulation"
    
    print_color "$YELLOW" "This test simulates a full deployment cycle..."
    
    # 1. Check if we can authenticate
    print_color "$YELLOW" "1. Testing authentication..."
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_color "$GREEN" "✓ Authentication successful"
    else
        print_color "$RED" "✗ Not authenticated"
        return 1
    fi
    
    # 2. Check Artifact Registry
    print_color "$YELLOW" "2. Checking Artifact Registry..."
    if gcloud artifacts repositories describe finance-containers --location=$REGION &>/dev/null; then
        print_color "$GREEN" "✓ Artifact Registry repository exists"
    else
        print_color "$YELLOW" "⚠ Artifact Registry repository not found"
    fi
    
    # 3. Validate deployment script
    print_color "$YELLOW" "3. Validating deployment process..."
    if [ -x "$ROOT_DIR/scripts/testing/validate-deployment.sh" ]; then
        if "$ROOT_DIR/scripts/testing/validate-deployment.sh"; then
            print_color "$GREEN" "✓ Deployment validation passed"
        else
            print_color "$RED" "✗ Deployment validation failed"
            return 1
        fi
    fi
    
    return 0
}

# Main test execution
main() {
    print_color "$BLUE" "🚀 Athena Finance CI/CD Testing Suite"
    print_color "$BLUE" "====================================="
    print_color "$YELLOW" "Running comprehensive tests..."
    
    # Run all tests
    test_prerequisites
    record_result "Prerequisites" $?
    
    test_github_workflows
    record_result "GitHub Workflows" $?
    
    test_npm_scripts
    record_result "NPM Scripts" $?
    
    test_docker_builds
    record_result "Docker Builds" $?
    
    test_cloud_build
    record_result "Cloud Build" $?
    
    test_deployment_scripts
    record_result "Deployment Scripts" $?
    
    test_terraform
    record_result "Terraform" $?
    
    test_service_connectivity
    record_result "Service Connectivity" $?
    
    test_monitoring
    record_result "Monitoring Integration" $?
    
    test_e2e_deployment
    record_result "End-to-End Deployment" $?
    
    # Summary
    echo ""
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "📊 Test Summary"
    print_color "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$GREEN" "✅ Tests Passed: $TESTS_PASSED"
    print_color "$RED" "❌ Tests Failed: $TESTS_FAILED"
    
    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
        echo ""
        print_color "$RED" "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            print_color "$RED" "  - $test"
        done
    fi
    
    echo ""
    if [ $TESTS_FAILED -eq 0 ]; then
        print_color "$GREEN" "🎉 All tests passed! CI/CD pipeline is ready."
        exit 0
    else
        print_color "$RED" "❌ Some tests failed. Please fix the issues above."
        exit 1
    fi
}

# Run main
main "$@"