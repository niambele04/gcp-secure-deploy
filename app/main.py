import os
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def root():
    return {
        "message": "Hello from Cloud Run",
        "projet": "Déploiement sécurisé GCP : Terraform, CI/CD, Trivy",
        "auteur": "Siata Niambele",
        "env": os.getenv("APP_ENV", "dev"),
    }

@app.get("/health")
def health():
    return {"status": "ok"}