# Global ARG must be declared before the first FROM to be available in all FROM instructions.
ARG PYTHON_VERSION=3.12

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
FROM python:${PYTHON_VERSION}-slim AS app_build
ARG PYTHON_VERSION=3.12
ARG APP_VERSION=0.0.0

# setuptools_scm can't find git tags inside the build container,
# so we pass the version in explicitly via a build arg.
ENV SETUPTOOLS_SCM_PRETEND_VERSION=${APP_VERSION}

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /src
COPY . /src

# Create the venv explicitly at /app, then sync the project into it.
# Using VIRTUAL_ENV is more reliable than UV_PROJECT_ENVIRONMENT
# for uv sync in a container build context.
RUN uv venv /app --python python${PYTHON_VERSION}
RUN --mount=type=cache,target=/root/.cache/uv \
    VIRTUAL_ENV=/app uv sync --locked --no-editable --no-dev

# Hard verification: fail the build loudly if tiled isn't where we expect it.
RUN test -f /app/bin/tiled || (echo "ERROR: /app/bin/tiled not found after uv sync" && exit 1)

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

# Smoke test: verify tiled is on PATH and returns the correct version.
RUN which tiled && tiled --version

RUN mkdir -p /app/share/tiled && \
    touch /app/share/tiled/.identifying_file_72628d5f953b4229b58c9f1f8f6a9a09

EXPOSE 8000

ENTRYPOINT []
CMD ["tiled", "serve", "config", "--host", "0.0.0.0", "--port", "8000", "--scalable"]
