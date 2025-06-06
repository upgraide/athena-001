# GitHub Repository Setup Guide

## Quick Setup Commands

Run these commands in order:

```bash
# 1. Authenticate with GitHub (if not already done)
gh auth login

# 2. Create the repository
gh repo create upgraide/athena-001 --public --description "AI-powered finance automation platform"

# 3. Add the remote to your local repository
git remote add origin https://github.com/upgraide/athena-001.git

# 4. Push your code
git push -u origin main

# 5. Set up Workload Identity Federation and GitHub secrets
./scripts/setup/setup-github-secrets.sh

# 6. Verify the setup
gh workflow list --repo upgraide/athena-001
```

## What This Sets Up

1. **GitHub Repository**: Creates `upgraide/athena-001` repository
2. **CI/CD Pipelines**: 
   - CI runs on every push and PR
   - CD deploys to staging automatically, production with approval
3. **GitHub Secrets**:
   - `WIF_PROVIDER`: Workload Identity Provider for keyless auth
   - `WIF_SERVICE_ACCOUNT`: Service account for deployments
   - `GCP_PROJECT_ID`: Your Google Cloud project ID
4. **Workload Identity Federation**: Keyless authentication between GitHub and GCP

## Verify Everything Works

After pushing, check:

1. **Actions Tab**: https://github.com/upgraide/athena-001/actions
   - You should see the CI workflow running
   - It will run tests, linting, and security checks

2. **Secrets**: https://github.com/upgraide/athena-001/settings/secrets/actions
   - You should see 3 secrets configured

3. **First Deployment**:
   - The CD pipeline will trigger after CI passes on the main branch
   - Staging deployment is automatic
   - Production requires manual approval

## Troubleshooting

If the workflows fail:

1. **Authentication Issues**: 
   - Check that WIF is properly configured
   - Run: `./scripts/setup/setup-github-wif.sh upgraide/athena-001`

2. **Missing Secrets**:
   - Re-run: `./scripts/setup/setup-github-secrets.sh`
   - Manually add via GitHub UI if needed

3. **Permission Issues**:
   - Ensure the service account has necessary permissions
   - Check Cloud Run and Artifact Registry permissions