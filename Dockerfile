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
# Production build stage: clean Python image + fresh uv, no devcontainer baggage
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim AS app_build
ARG PYTHON_VERSION=3.12

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# - copy mode avoids hard-link issues in containers
# - bytecode compilation for faster startup
# - never download Python (use the base image's interpreter)
# - point uv at the base image Python
# - install venv directly at /app (no .venv subdirectory)
ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_PYTHON=python${PYTHON_VERSION} \
    UV_PROJECT_ENVIRONMENT=/app

WORKDIR /src
COPY . /src

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-editable --no-dev

##########################################################################
# Production runtime stage: same slim Python base so venv symlinks resolve
FROM python:${PYTHON_VERSION}-slim AS app_runtime
ARG PYTHON_VERSION=3.12

# Add the application virtualenv to search path.
ENV PATH=/app/bin:$PATH

STOPSIGNAL SIGINT

# Don't run your app as root.
RUN groupadd -r app && \
    useradd -r -d /app -g app -N app

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /deploy/config && chown -R app:app /deploy/config
COPY example_configs/single_catalog_single_user.yml /deploy/config
ENV TILED_CONFIG=/deploy/config

# Copy the pre-built venv (which IS /app) from the build stage.
COPY --from=app_build --chown=app:app /app /app

USER app
WORKDIR /app

# Smoke test that the application can be imported.
RUN python -V && \
    python -c 'import test_dls_tiled'

RUN mkdir -p /app/share/tiled && \
    touch /app/share/tiled/.identifying_file_72628d5f953b4229b58c9f1f8f6a9a09

EXPOSE 8000

ENTRYPOINT []
CMD ["tiled", "serve", "config", "--host", "0.0.0.0", "--port", "8000", "--scalable"]
