This branch keeps the FBC push trigger for `v4.20/rhtas-operator`, but rewires it
for isolated pipeline testing.

Safety changes in `.tekton/rhtas-fbc-v4-20-push.yaml`:
- triggers only on pushes to branch `fbc-test-v4-20`
- resolves `fbc-builder` from `securesign/pipelines` branch `validate-fbc-graph-sync`
- mounts a temporary workspace PVC for the pipeline run
- uses test application/component labels instead of the standard `rhtas-fbc` labels

Intended use:
- push changes on this branch to exercise the updated Tekton pipeline
- validate the pre-build FBC checks without building or publishing catalog images

Trigger note:
- README-only updates can be used as no-op commits when you need to rerun this test branch manually
