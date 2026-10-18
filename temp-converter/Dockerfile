FROM python:3.12-slim AS build

WORKDIR /build
RUN python -m venv /venv
COPY app/requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt


FROM python:3.12-slim

ARG APP_VERSION=dev

LABEL org.opencontainers.image.title="temp-converter"
LABEL org.opencontainers.image.source="https://github.com/manish-gitx/assignment-cloud"
LABEL org.opencontainers.image.revision=$APP_VERSION

RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /srv
COPY --from=build /venv /venv
COPY app/ ./app/

ENV PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_VERSION=$APP_VERSION

USER 10001
EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", \
     "--worker-tmp-dir", "/tmp", "--no-control-socket", "--graceful-timeout", "20", "app.app:app"]
