# The devcontainer should use the developer target and run as root with podman
# or docker with user namespaces.
FROM ghcr.io/diamondlightsource/ubuntu-devcontainer:noble AS developer

# Add any system dependencies for the developer/build environment here
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    graphviz \
    && apt-get dist-clean

# The build stage installs the context into the venv
FROM developer AS build

# Change the working directory to the `app` directory
# and copy in the project
WORKDIR /app
COPY . /app
RUN chmod o+wrX .

# Tell uv sync to install python in a known location so we can copy it out later
ENV UV_PYTHON_INSTALL_DIR=/python

# Sync the project without its dev dependencies
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-editable --no-dev


FROM build AS debug


# Set origin to use ssh
RUN git remote set-url origin git@github.com:hyperrealist/test-dls-tiled.git


# For this pod to understand finding user information from LDAP
RUN apt update
RUN DEBIAN_FRONTEND=noninteractive apt install libnss-ldapd -y
RUN sed -i 's/files/ldap files/g' /etc/nsswitch.conf

# Make editable and debuggable
RUN uv pip install debugpy
RUN uv pip install -e .
ENV PATH=/app/.venv/bin:$PATH

# Alternate entrypoint to allow devcontainer to attach
ENTRYPOINT [ "/bin/bash", "-c", "--" ]
CMD [ "while true; do sleep 30; done;" ]


##########################################################################
# Production build stage: installs project as non-editable package

FROM build AS app_build

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-editable --no-dev


##########################################################################
# Production runtime stage: minimal image with only runtime dependencies

FROM ubuntu:noble AS app_runtime

# Ensure logs and error messages do not get stuck in a buffer.
ENV PYTHONUNBUFFERED=1
ENV PATH=/app/bin:$PATH

# Don't run your app as root.
RUN groupadd -r app && \
    useradd -r -d /app -g app -N app

# Install only runtime dependencies
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy the pre-built venv from app_build stage
COPY --from=app_build --chown=app:app /python /python
COPY --from=app_build --chown=app:app /app/.venv /app

# Set ownership and create app directory
RUN mkdir -p /app && chown -r app:app /app

USER app
WORKDIR /app

# Smoke test that the application can be imported
RUN python -V && \
    python -c 'import test_dls_tiled'

EXPOSE 8000

CMD ["tiled", "serve", "config", "--host", "0.0.0.0", "--port", "8000", "--scalable"]
