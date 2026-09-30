FROM mcr.microsoft.com/cbl-mariner/base/core:2.0

LABEL org.opencontainers.image.title="Azure Local POC smoke container"
LABEL org.opencontainers.image.description="Minimal no-secret container used to validate Docker build plumbing before AKS exists."

RUN tdnf install -y ca-certificates shadow-utils && tdnf clean all
RUN useradd --create-home --shell /sbin/nologin appuser
USER appuser

CMD ["/bin/sh", "-c", "echo Azure Local POC smoke container ready && sleep 3600"]