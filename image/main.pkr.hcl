data "amazon-ami" "amazon-linux-2" {
  owners = ["amazon"]
  most_recent = true
  region = var.region
  filters = {
    virtualization-type = "hvm"
    name = "amzn2-ami-hvm-*-x86_64-gp2"
    root-device-type = "ebs"
  }
}

source "amazon-ebs" "main" {
  ami_name = "demo-app-image-{{timestamp}}"
  region = var.region
  profile = "default"
  instance_type = "t3.micro"
  ssh_username = "ec2-user"
  source_ami = data.amazon-ami.amazon-linux-2.id
  tag {
    key = "Name"
    value = "demo-app-image"
  }
}

build {
  sources = ["source.amazon-ebs.main"]
  provisioner "file" {
    source = "../fluent-bit/fluent-bit.conf"
    destination = "/tmp/fluent-bit.conf"
  }
  provisioner "shell" {
    script = "install.sh"
    execute_command = "echo 'packer' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
  }
}