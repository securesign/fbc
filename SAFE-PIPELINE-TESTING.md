This branch keeps the FBC push trigger for `v4.20/rhtas-operator`, but rewires it
for isolated pipeline testing.

Safety changes in `.tekton/rhtas-fbc-v4-20-push.yaml`:
- triggers only on pushes to branch `fbc-test-v4-20`
- resolves `fbc-builder` from `securesign/pipelines` branch `validate-fbc-graph-sync`
- pushes to `quay.io/securesign/fbc-v4-20-pipeline-test:{{revision}}`
- uses test application/component labels instead of the standard `rhtas-fbc` labels

Intended use:
- push changes on this branch to exercise the updated Tekton pipeline
- keep catalog source content realistic while avoiding the standard live image name
