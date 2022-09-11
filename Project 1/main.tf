# sanmols @ 2022 
# Website deployment via Terraform

# Objective: Deploying Apache Server on a custom VPC and setting up routing. 

# Configure the AWS provider 

provider "aws" {
  region     = "us-east-1"
  access_key = var.ACCESS_KEY
  secret_key = var.SECRET_KEY
}



# Create a VPC | Class B address

resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    "Name" = "Prod_VPC"
  }
}

# Create an Internet Gateway 

resource "aws_internet_gateway" "prod_ig" {
  vpc_id = aws_vpc.prod_vpc.id
  tags = {
    Name = "Prod_IG"
  }
}


# Create a Route Table for the VPC 
# (OPTIONAL: IPv6)

resource "aws_route_table" "prod_route" {
  vpc_id = aws_vpc.prod_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod_ig.id
  }

# Changed 'Egress Only Gateway ID' to 'Gateway ID' for IPv6 
  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.prod_ig.id
  }

  tags = {
    Name = "Prod_Route"
  }
}

# Create AWS Subnet | Class C single subnet

resource "aws_subnet" "prod_subnet1" {
  vpc_id            = aws_vpc.prod_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    "Name" = "Prod_Sub1"
  }

}

# Associate the Subnet1 with the Route Table 

resource "aws_route_table_association" "prod_accociate_route" {
  subnet_id      = aws_subnet.prod_subnet1.id
  route_table_id = aws_route_table.prod_route.id
}

# Create and Setup AWS Security Group for EC2 
# Allow traffic from public internet to Port 22, 80, 443 

resource "aws_security_group" "prod_security" {
  name        = "allow_web_traffic"
  description = "Allow Web Inbound Traffic"
  vpc_id      = aws_vpc.prod_vpc.id

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "Allow_Web"
  }
}

# Create AWS Networking Interface 

resource "aws_network_interface" "prod_ni" {
  subnet_id       = aws_subnet.prod_subnet1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.prod_security.id]

}

# Create the elastic IP for the list of IP(s) in Network Interface 

## NOTE: Elastic IP is a resource that won't form without having an Internet Gateway (Refer documentation for more information)
## Setting up a 'depends_on' attribute to reference the whole resources presences before provisioning. 

resource "aws_eip" "prod_elastic" {
  vpc                       = true
  network_interface         = aws_network_interface.prod_ni.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.prod_ig]
}


resource "aws_instance" "prod_instance" {
  ami               = "ami-052efd3df9dad4825"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "my_key_rsa"

  network_interface {
    network_interface_id = aws_network_interface.prod_ni.id
    device_index         = 0
  }

# Tags to start and end 
  user_data = <<-EOF
        #!/bin/bash
        sudo apt update -y
        sudo apt install apache2 -y
        sudo systemctl start apache2
        sudo echo "The page was created by the user data" | sudo tee /var/www/html/index.html
        EOF

  tags = {
    Name = "Web_Server_via_Terraform"
  }

}

output "server_instance_id"{
  value = aws_instance.prod_instance.id
}

output "server_public_ip"{
  value = aws_instance.prod_instance.public_ip
}