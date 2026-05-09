"""
Aplicação de demonstração para blue-green e canary deployments.
Fornece endpoints de health check, métricas Prometheus e informações de versão.
"""

import os
import socket
import time
import logging
from datetime import datetime, timezone
from flask import Flask, jsonify, request
from prometheus_client import (
    Counter,
    Histogram,
    Gauge,
    generate_latest,
    CONTENT_TYPE_LATEST,
)

# Configuração de logging estruturado
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# =============================================================================
# Variáveis de configuração via environment variables
# =============================================================================
APP_VERSION  = os.getenv("APP_VERSION", "0.0.1")
BUILD_DATE   = os.getenv("BUILD_DATE", "unknown")
GIT_COMMIT   = os.getenv("GIT_COMMIT", "unknown")
SLOT         = os.getenv("SLOT", "unknown")       # blue, green ou canary
ENVIRONMENT  = os.getenv("ENVIRONMENT", "development")
HOSTNAME     = socket.gethostname()

# =============================================================================
# Métricas Prometheus
# =============================================================================
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Número total de requisições HTTP",
    ["method", "endpoint", "status_code", "slot"],
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Latência das requisições HTTP em segundos",
    ["method", "endpoint", "slot"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)

APP_INFO = Gauge(
    "app_info",
    "Informações da aplicação",
    ["version", "slot", "environment", "hostname"],
)

HEALTH_STATUS = Gauge(
    "app_health_status",
    "Status de saúde da aplicação (1=saudável, 0=não saudável)",
)

# Registra informações estáticas da app
APP_INFO.labels(
    version=APP_VERSION,
    slot=SLOT,
    environment=ENVIRONMENT,
    hostname=HOSTNAME,
).set(1)

HEALTH_STATUS.set(1)

# Timestamp de inicialização
START_TIME = datetime.now(timezone.utc)


# =============================================================================
# Middleware para métricas automáticas
# =============================================================================
@app.before_request
def before_request():
    """Registra o timestamp de início da requisição."""
    request._start_time = time.time()


@app.after_request
def after_request(response):
    """Registra métricas de duração e contagem após cada requisição."""
    duration = time.time() - getattr(request, "_start_time", time.time())
    endpoint = request.endpoint or "unknown"

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=endpoint,
        status_code=response.status_code,
        slot=SLOT,
    ).inc()

    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=endpoint,
        slot=SLOT,
    ).observe(duration)

    return response


# =============================================================================
# Endpoints
# =============================================================================

@app.route("/", methods=["GET"])
def index():
    """
    Endpoint raiz: retorna informações básicas da aplicação.
    Útil para verificar rapidamente qual versão e slot estão servindo tráfego.
    """
    uptime_seconds = (datetime.now(timezone.utc) - START_TIME).total_seconds()

    return jsonify({
        "app": "gcp-azure-devops-platform",
        "version": APP_VERSION,
        "slot": SLOT,
        "environment": ENVIRONMENT,
        "hostname": HOSTNAME,
        "uptime_seconds": round(uptime_seconds, 2),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }), 200


@app.route("/health", methods=["GET"])
def health():
    """
    Health check endpoint.
    Retorna 200 se a aplicação está saudável, 503 caso contrário.
    Verificado pelo Kubernetes livenessProbe e readinessProbe.
    """
    checks = {}
    all_healthy = True

    # Verifica memória disponível (simulação)
    try:
        with open("/proc/meminfo") as f:
            meminfo = f.read()
        mem_available = int([l for l in meminfo.split("\n") if "MemAvailable" in l][0].split()[1])
        checks["memory"] = {
            "status": "ok" if mem_available > 100000 else "warning",
            "available_kb": mem_available,
        }
    except Exception:
        checks["memory"] = {"status": "ok", "available_kb": "unknown"}

    # Verificação de uptime
    uptime = (datetime.now(timezone.utc) - START_TIME).total_seconds()
    checks["uptime"] = {
        "status": "ok",
        "seconds": round(uptime, 2),
    }

    # Verificação do slot (blue/green/canary)
    checks["slot"] = {
        "status": "ok",
        "current": SLOT,
    }

    overall_status = "ok" if all_healthy else "degraded"
    http_status = 200 if all_healthy else 503

    HEALTH_STATUS.set(1 if all_healthy else 0)

    return jsonify({
        "status": overall_status,
        "version": APP_VERSION,
        "slot": SLOT,
        "hostname": HOSTNAME,
        "checks": checks,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }), http_status


@app.route("/ready", methods=["GET"])
def readiness():
    """
    Readiness probe: indica se o pod está pronto para receber tráfego.
    Diferente do health, pode retornar 503 durante warm-up sem matar o pod.
    """
    uptime = (datetime.now(timezone.utc) - START_TIME).total_seconds()

    # Aguarda 5 segundos de warm-up antes de aceitar tráfego
    if uptime < 5:
        return jsonify({
            "ready": False,
            "reason": "warm-up em andamento",
            "uptime_seconds": round(uptime, 2),
        }), 503

    return jsonify({
        "ready": True,
        "slot": SLOT,
        "uptime_seconds": round(uptime, 2),
    }), 200


@app.route("/metrics", methods=["GET"])
def metrics():
    """
    Endpoint de métricas Prometheus.
    Coletado automaticamente pelo Prometheus/Google Managed Prometheus/Azure Monitor.
    """
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.route("/version", methods=["GET"])
def version():
    """
    Retorna informações detalhadas sobre a versão deployada.
    Útil para confirmar qual versão está em produção após blue-green ou canary.
    """
    return jsonify({
        "app_version": APP_VERSION,
        "build_date": BUILD_DATE,
        "git_commit": GIT_COMMIT,
        "slot": SLOT,
        "environment": ENVIRONMENT,
        "hostname": HOSTNAME,
        "python_version": __import__("sys").version,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }), 200


@app.route("/env", methods=["GET"])
def environment_info():
    """
    Retorna variáveis de ambiente não-sensíveis.
    Útil para debugging de configuração entre slots.
    """
    safe_env_keys = [
        "APP_VERSION", "BUILD_DATE", "GIT_COMMIT", "SLOT",
        "ENVIRONMENT", "PORT", "LOG_LEVEL",
    ]
    env_info = {k: os.getenv(k, "não definido") for k in safe_env_keys}

    return jsonify({
        "environment_variables": env_info,
        "hostname": HOSTNAME,
        "slot": SLOT,
    }), 200


# =============================================================================
# Handlers de erro
# =============================================================================

@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "endpoint não encontrado", "status": 404}), 404


@app.errorhandler(500)
def internal_error(e):
    logger.error("Erro interno: %s", str(e))
    return jsonify({"error": "erro interno do servidor", "status": 500}), 500


# =============================================================================
# Inicialização
# =============================================================================

if __name__ == "__main__":
    port = int(os.getenv("PORT", "8080"))
    debug = os.getenv("FLASK_DEBUG", "false").lower() == "true"

    logger.info(
        "Iniciando %s versão %s no slot %s (ambiente: %s)",
        "devops-platform-app",
        APP_VERSION,
        SLOT,
        ENVIRONMENT,
    )

    app.run(host="0.0.0.0", port=port, debug=debug)
