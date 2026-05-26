## Plan: ArcBox ITPro-Only Conservative Cleanup

Keep ArcBox ITPro functionality intact while removing non-ITPro ArcBox components (DevOps/DataOps/LocalBox pipelines and flavor-specific artifacts) within ArcBox scope only. Preserve shared templates/scripts and flavor conditionals to minimize regression risk and enable quick rollback.

**Steps**
1. Baseline and safety checks
- Confirm current references to DevOps/DataOps/LocalBox ArcBox assets and capture a pre-change inventory for auditability.
- Validate that ITPro pipelines and ITPro integration test definitions remain present and unchanged.

2. Phase 1: Remove non-ITPro pipeline entry points (parallel with step 3)
- Delete ArcBox DevOps/DataOps pipeline YAMLs and destroy YAMLs.
- Delete LocalBox pipeline YAMLs only where they are part of ArcBox pipeline scope cleanup.
- Keep ITPro pipeline and ITPro destroy pipeline unchanged.

3. Phase 2: Remove non-ITPro ArcBox artifacts (parallel with step 2)
- Delete DevOps-only ArcBox files: DevOps logon/test/DSC/workbook, GitOps scripts, ingress manifests, and longhorn manifest.
- Delete DataOps-only ArcBox files: DataOps logon/app/test/DSC/workbook files and Arc Data Services deployment templates/scripts.
- Keep shared ArcBox scripts/modules and ITPro-specific files.

4. Phase 3: Remove non-ITPro Kubernetes module files that are only used by non-ITPro flavors (depends on 3)
- Delete ArcBox Kubernetes Bicep files associated with DevOps/DataOps runtime paths.
- Do not edit shared root templates in conservative mode; leave dormant conditionals in place.

5. Phase 4: Update ArcBox-scoped workflow/docs that expose non-ITPro flavor options (depends on 2,3,4)
- Update ArcBox manual execution workflow flavor choices to ITPro only.
- Update ArcBox-scoped references that point to removed ArcBox flavor pipelines/files.
- Do not perform repo-wide doc normalization outside ArcBox scope.

6. Phase 5: Verification and rollback readiness (depends on 2-5)
- Run static reference scans to ensure no kept ArcBox ITPro path references deleted files.
- Validate YAML parsing for remaining ArcBox pipeline/workflow files.
- Validate ITPro deployment path assumptions (flavor=ITPro) remain unchanged.
- Produce deletion manifest and impact summary for PR review.

**Relevant files**
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_arcbox_itpro.yml — Keep as primary ArcBox ITPro deployment pipeline.
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_arcbox_itpro_destroy.yml — Keep as ArcBox ITPro cleanup pipeline.
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_arcbox_devops.yml — Remove.
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_arcbox_devops_destroy.yml — Remove.
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_arcbox_dataops.yml — Remove.
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_arcbox_dataops_destroy.yml — Remove.
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_localbox.yml — Remove in current scope decision.
- c:\dev\repos\AzureSessions\azure_arc\.azure-pipelines\azure_jumpstart_localbox_destroy.yml — Remove in current scope decision.
- c:\dev\repos\AzureSessions\azure_arc\azure_jumpstart_arcbox\artifacts\Bootstrap.ps1 — Keep unchanged in conservative mode; verify ITPro references only remain valid.
- c:\dev\repos\AzureSessions\azure_arc\azure_jumpstart_arcbox\artifacts\tests\Invoke-Test.ps1 — Keep unchanged in conservative mode.
- c:\dev\repos\AzureSessions\azure_arc\azure_jumpstart_arcbox\artifacts\ArcServersLogonScript.ps1 — Keep unchanged in conservative mode.
- c:\dev\repos\AzureSessions\azure_arc\azure_jumpstart_arcbox\bicep\main.bicep — Keep unchanged in conservative mode.
- c:\dev\repos\AzureSessions\azure_arc\.github\workflows\manual-arcBox-execution-with-parameters.yaml — Update flavor options to ITPro-only.

**Verification**
1. Run reference scan for removed flavor keywords and removed filenames under ArcBox scope, then inspect any hits in kept files.
2. Validate remaining ArcBox pipeline/workflow YAML files parse cleanly.
3. Validate ArcBox ITPro integration test descriptors are still reachable from kept pipeline path.
4. Optional dry-run: queue ITPro pipeline with default parameters and confirm expected stage graph includes deployment, test publish, and cleanup paths.

**Decisions**
- Included: Conservative cleanup (delete non-ITPro files only), ArcBox-scoped changes.
- Excluded: Refactoring shared Bicep/ARM/PowerShell flavor conditionals; repo-wide non-ArcBox docs/templates cleanup.
- Rationale: Minimize behavioral regression while meeting objective to keep ArcBox for IT pros content.

**Further Considerations**
1. Follow-up hardening pass can remove dead flavor branches from shared templates/scripts after this cleanup stabilizes.
2. Keep a short allowlist of retained ArcBox ITPro paths in PR notes to simplify future maintenance.
