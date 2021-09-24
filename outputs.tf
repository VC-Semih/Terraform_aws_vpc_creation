output "public_subnets" {
  value = [for subnet in aws_subnet.public : subnet.id]
}