resource "aws_security_group" "elb-security-group" {
  count  = "${var.common-elb-sg-enabled ? 1 : 0}"
  vpc_id = "${var.vpc-id}"

  name                   = "elb.${var.cluster-name}"
  description            = "Security group for Kubernetes ELB (Common)"
  revoke_rules_on_delete = "true"

  tags {
    Name = "elb.${var.cluster-name}"
  }

}

resource "aws_security_group_rule" "elb-security-group-ingress" {
  count             = "${var.common-elb-sg-enabled && var.common-elb-sg-default-ingress ? 1 : 0}"
  security_group_id = "${var.common-elb-sg-enabled && var.common-elb-sg-default-ingress ? "${join("", aws_security_group.elb-security-group.*.id)}" : ""}"
  type              = "ingress"

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "elb-security-group-egress" {
  count             = "${var.common-elb-sg-enabled && var.common-elb-sg-default-egress ? 1 : 0}"
  security_group_id = "${var.common-elb-sg-enabled && var.common-elb-sg-default-egress ? "${join("", aws_security_group.elb-security-group.*.id)}" : ""}"
  type              = "egress"

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
