# =============================================================================
# Dockerfile multi-stage — Aplicação Flask para Blue-Green e Canary deploys
# =============================================================================
# Stage 1: Builder — instala dependências em ambiente isolado
# Stage 2: Runtime — imagem mínima de produção, non-root
# =============================================================================

# Stage 1: Builder
FROM python:3.11-slim AS builder

# Instala dependências do sistema para compilação
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia apenas requirements primeiro (otimiza cache do Docker)
COPY requirements.txt .

# Instala dependências em diretório isolado (para copiar no stage final)
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# =============================================================================
# Stage 2: Runtime (imagem de produção)
# =============================================================================
FROM python:3.11-slim AS runtime

# Argumentos de build para metadados da imagem
ARG APP_VERSION="0.0.1"
ARG BUILD_DATE="unknown"
ARG GIT_COMMIT="unknown"

# Labels OCI standard para rastreabilidade
LABEL org.opencontainers.image.title="GCP Azure DevOps Platform — Sample App"
LABEL org.opencontainers.image.description="Aplicação Flask para demonstração de blue-green e canary deployments"
LABEL org.opencontainers.image.version="${APP_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.source="https://github.com/leandroninja/gcp-azure-devops-platform"
LABEL org.opencontainers.image.licenses="MIT"

# Instala apenas dependências de runtime necessárias
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Cria usuário não-root para executar a aplicação (princípio do least privilege)
RUN groupadd --gid 1001 appuser && \
    useradd --uid 1001 --gid 1001 --no-create-home --shell /bin/false appuser

WORKDIR /app

# Copia dependências instaladas do stage builder
COPY --from=builder /install /usr/local

# Copia código da aplicação
COPY --chown=appuser:appuser app.py .

# Define variáveis de ambiente padrão (sobrescritas em runtime via k8s)
ENV APP_VERSION="${APP_VERSION}" \
    BUILD_DATE="${BUILD_DATE}" \
    GIT_COMMIT="${GIT_COMMIT}" \
    SLOT="unknown" \
    ENVIRONMENT="production" \
    PORT="8080" \
    PYTHONDONTWRITEBYTECODE="1" \
    PYTHONUNBUFFERED="1" \
    PYTHONFAULTHANDLER="1"

# Altera para usuário não-root
USER appuser

# Expõe porta da aplicação (documentação, não abre porta automaticamente)
EXPOSE 8080

# Health check built-in do Docker (Kubernetes usa suas próprias probes)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Inicia com gunicorn para produção
# - 4 workers (regra: 2*CPU+1)
# - timeout de 120 segundos
# - logs no stdout para coleta pelo Kubernetes
CMD ["gunicorn", \
     "--bind", "0.0.0.0:8080", \
     "--workers", "4", \
     "--worker-class", "sync", \
     "--timeout", "120", \
     "--keep-alive", "5", \
     "--log-level", "info", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--capture-output", \
     "app:app"]
