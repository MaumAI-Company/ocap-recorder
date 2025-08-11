I have current changes that represent the new version of a remote repository. I need you to apply the series of commits with hash 7c504ee ~ face5bd from the "patch" branch to maintain our customizations on top of these current changes. 

Please use only Git commands to accomplish this task. The specific steps should be:
1. First, examine the current state of the repository and the "patch" branch
2. Identify the series of commit hashes that starts with "7c504ee" and ends with "face5bd" in the "patch" branch
3. Apply these commits (likely using git cherry-pick or similar Git operation) into "main" only for files under `projects/` and `scripts/` to preserve our customizations
4. Ensure the customizations are properly integrated with the new remote repository version

Use Git commands exclusively - do not manually edit files or use other tools for this operation.