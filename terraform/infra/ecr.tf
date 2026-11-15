# -----------------------------------------------------------------------------
# ecr.tf - private Docker image registry for the app.
# The pipeline pushes the image here; the worker nodes pull it from here.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name = "${var.projectname}-app"

  # Lets `terraform destroy` delete the repository even if it contains images.
  force_delete = true

  # Check every pushed image for known security vulnerabilities.
  image_scanning_configuration {
    scan_on_push = true
  }
}
