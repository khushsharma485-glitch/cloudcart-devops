output "public_ip" {
  description = "CloudCart's public address: http://<public_ip>/api/products"
  value       = oci_core_instance.k3s.public_ip
}

output "ssh_command" {
  value = "ssh ubuntu@${oci_core_instance.k3s.public_ip}"
}

output "bootstrap_command" {
  description = "Installs Argo CD and hands the cluster over to Git."
  value       = "scripts/oci/bootstrap.sh ${oci_core_instance.k3s.public_ip}"
}
