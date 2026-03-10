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
# UV_PROJECT_ENVIRONMENT=/app installs the venv directly into /app,
# matching the upstream Tiled container approach so /app/bin/tiled exists.

FROM developer AS app_build
WORKDIR /src
COPY . /src

ENV UV_PYTHON_INSTALL_DIR=/python
ENV UV_PROJECT_ENVIRONMENT=/app

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-editable --no-dev


##########################################################################
# Production runtime stage: minimal image with only runtime dependencies

FROM ubuntu:noble AS app_runtime

# Ensure logs and error messages do not get stuck in a buffer.
ENV PYTHONUNBUFFERED=1
ENV PATH=/app/bin:/python/bin:$PATH

# Don't run your app as root.
RUN groupadd -r app && \
    useradd -r -d /app -g app -N app

# Install only runtime dependencies
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy the python interpreter and the venv (which IS /app) from the build stage
COPY --from=app_build --chown=app:app /python /python
COPY --from=app_build --chown=app:app /app /app

# Create config directory and copy example config
RUN mkdir -p /deploy/config && chown -R app:app /deploy/config
COPY example_configs/single_catalog_single_user.yml /deploy/config
ENV TILED_CONFIG=/deploy/config

RUN touch /app/.venv/share/tiled/.identifying_file_72628d5f953b4229b58c9f1f8f6a9a09

USER app
WORKDIR /app

# Smoke test that the application can be imported
RUN python -V && \
    python -c 'import test_dls_tiled'

EXPOSE 8000

CMD ["tiled", "serve", "config", "--host", "0.0.0.0", "--port", "8000", "--scalable"]
