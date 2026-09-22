# The base image is expected to contain
## /bin/opm (with a serve subcommand) and /bin/grpc_health_probe
# Trigger the RHTAS 1.3.8 catalog rebuild.
FROM brew.registry.redhat.io/rh-osbs/openshift-ose-operator-registry-rhel9:v4.18

ENTRYPOINT ["/bin/opm"]
CMD ["serve", "/configs", "--cache-dir=/tmp/cache"]

ADD licenses/ /licenses/
ADD catalog /configs
RUN ["/bin/opm", "serve", "/configs", "--cache-dir=/tmp/cache", "--cache-only"]

LABEL operators.operatorframework.io.index.configs.v1=/configs
