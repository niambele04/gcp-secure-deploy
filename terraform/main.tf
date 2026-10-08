terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" { type = string }
variable "region" {
  type    = string
  default = "europe-west9"
}
variable "image" {
  type    = string
  default = "us-docker.pkg.dev/cloudrun/container/hello" # image de test, remplacée par le CI/CD
}

# 1. Activer les API
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# 2. Dépôt d'images
resource "google_artifact_registry_repository" "apps" {
  repository_id = "apps"
  format        = "DOCKER"
  location      = var.region
  depends_on    = [google_project_service.apis]
}

# 3. Compte de service dédié à l'application
resource "google_service_account" "run_sa" {
  account_id   = "api-runtime"
  display_name = "Identité d'exécution de l'API (moindre privilège)"
  depends_on   = [google_project_service.apis]
}

# 4. Secret + droit de lecture uniquement pour ce compte
resource "google_secret_manager_secret" "api_key" {
  secret_id  = "api-key"
  depends_on = [google_project_service.apis]
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "api_key_v1" {
  secret      = google_secret_manager_secret.api_key.id
  secret_data = "valeur-de-demo-a-remplacer"
}

resource "google_secret_manager_secret_iam_member" "run_reads_secret" {
  secret_id = google_secret_manager_secret.api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.run_sa.email}"
}

# 5. Service Cloud Run
resource "google_cloud_run_v2_service" "api" {
  name     = "api"
  location = var.region

  template {
    service_account = google_service_account.run_sa.email
    containers {
      image = var.image
      env {
        name = "API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.api_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image] # l'image est gérée par le pipeline
  }

  depends_on = [google_secret_manager_secret_iam_member.run_reads_secret]
}

# 6. Accès public à l'API
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "url" {
  value = google_cloud_run_v2_service.api.uri
}