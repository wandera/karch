data "template_file" "cluster-spec" {
  template = "${file("${path.module}/templates/cluster-spec.yaml")}"

  vars {
    # Generic cluster configuration
    cluster-name       = "${aws_route53_record.cluster-root.name}"
    channel            = "${var.channel}"
    disable-sg-ingress = "${var.disable-sg-ingress}"
    elb-sg             = "${var.common-elb-sg-enabled ? "${join("", aws_security_group.elb-security-group.*.id)}" : ""}"
    cloud-labels       = "${join("\n", data.template_file.cloud-labels.*.rendered)}"
    kube-dns-domain    = "${var.kube-dns-domain}"
    kube-dns-provider  = "${var.kube-dns-provider}"
    kops-state-bucket  = "${var.kops-state-bucket}"

    master-lb-visibility     = "${var.master-lb-visibility == "Private" ? "Internal" : "Public"}"
    master-lb-dns-visibility = "${var.master-lb-visibility}"
    master-count             = "${length(var.master-availability-zones)}"
    master-lb-idle-timeout   = "${var.master-lb-idle-timeout}"

    kubernetes-version   = "${var.kubernetes-version}"
    vpc-cidr             = "${var.vpc-cidr-block}"
    vpc-id               = "${var.vpc-id}"
    trusted-cidrs        = "${join("\n", data.template_file.trusted-cidrs.*.rendered)}"
    subnets              = "${join("\n", data.template_file.subnets.*.rendered)}"
    container-networking = "${var.container-networking}"

    hooks = "${join("\n", data.template_file.hooks.*.rendered)}"

    # ETCD cluster parameters
    etcd-clusters = <<EOF
  - etcdMembers:
${join("\n", data.template_file.etcd-member.*.rendered)}
    name: main
    enableEtcdTLS: ${var.etcd-enable-tls}
    version: ${var.etcd-version}
${join("\n", data.template_file.backup-main.*.rendered)}
  - etcdMembers:
${join("\n", data.template_file.etcd-member.*.rendered)}
    name: events
    enableEtcdTLS: ${var.etcd-enable-tls}
    version: ${var.etcd-version}
${join("\n", data.template_file.backup-events.*.rendered)}
EOF

    # Kubelet configuration
    # CPU and Memory reservation for system/orchestration processes (soft)
    kubelet-eviction-flag = "${var.kubelet-eviction-flag}"

    kube-reserved-cpu      = "${var.kube-reserved-cpu}"
    kube-reserved-memory   = "${var.kube-reserved-memory}"
    system-reserved-cpu    = "${var.system-reserved-cpu}"
    system-reserved-memory = "${var.system-reserved-memory}"

    # APIServer configuration
    apiserver-storage-backend    = "etcd${substr(var.etcd-version, 0, 1)}"
    kops-authorization-mode      = "${var.rbac == "true" ? "rbac": "alwaysAllow"}"
    apiserver-authorization-mode = "${var.rbac == "true" ? "RBAC": "AlwaysAllow"}"
    rbac-super-user              = "${var.rbac == "true" ? "authorizationRbacSuperUser: ${var.rbac-super-user}" : ""}"

    apiserver-runtime-config = "${join("\n", data.template_file.apiserver-runtime-configs.*.rendered)}"
    oidc-config              = "${join("\n", data.template_file.oidc-apiserver-conf.*.rendered)}"

    # kube-controller-manager configuration
    hpa-sync-period      = "${var.hpa-sync-period}"
    hpa-scale-down-delay = "${var.hpa-scale-down-delay}"
    hpa-scale-up-delay   = "${var.hpa-scale-up-delay}"

    # Additional IAM policies for masters and nodes
    master-additional-policies = "${length(var.master-additional-policies) == 0 ? "" : format("master: |\n      %s", indent(6, var.master-additional-policies))}"
    node-additional-policies   = "${length(var.node-additional-policies) == 0 ? "" : format("node: |\n      %s", indent(6, var.node-additional-policies))}"

    # Log level for all master & kubelet components
    log-level = "${var.log-level}"
  }
}

data "template_file" "etcd-member" {
  count = "${length(var.master-availability-zones)}"

  template = <<EOF
    - encryptedVolume: true
      instanceGroup: master-$${az}
      name: $${az}
EOF

  vars {
    az = "${element(var.master-availability-zones, count.index)}"
  }
}

data "template_file" "backup-main" {
  count = "${var.etcd-backup-enabled ? 1 : 0}"

  template = <<EOF
    backups:
      backupStore: s3://${var.kops-state-bucket}/backups/${var.cluster-name}/etcd/main/
EOF
}

data "template_file" "backup-events" {
  count = "${var.etcd-backup-enabled ? 1 : 0}"

  template = <<EOF
    backups:
      backupStore: s3://${var.kops-state-bucket}/backups/${var.cluster-name}/etcd/events/
EOF
}

data "template_file" "trusted-cidrs" {
  count = "${length(var.trusted-cidrs)}"

  template = <<EOF
  - $${cidr}
EOF

  vars {
    cidr = "${element(var.trusted-cidrs, count.index)}"
  }
}

data "template_file" "cloud-labels" {
  count = "${length(keys(var.cloud-labels))}"

  template = <<EOF
    $${tag}: '$${value}'
EOF

  vars {
    tag   = "${element(keys(var.cloud-labels), count.index)}"
    value = "${element(values(var.cloud-labels), count.index)}"
  }
}

data "template_file" "subnets" {
  count = "${length(var.availability-zones)}"

  template = <<EOF
  - cidr: $${private-cidr}
    id: $${private-id}
    egress: $${nat-gateway}
    name: $${az}
    type: Private
    zone: $${az}
  - cidr: $${public-cidr}
    id: $${public-id}
    name: utility-$${az}
    type: Utility
    zone: $${az}
EOF

  vars {
    az           = "${element(var.availability-zones, count.index)}"
    nat-gateway  = "${element(var.nat-gateways, count.index)}"
    private-id   = "${element(var.vpc-private-subnet-ids, count.index)}"
    private-cidr = "${element(var.vpc-private-cidrs, count.index)}"
    public-id    = "${element(var.vpc-public-subnet-ids, count.index)}"
    public-cidr  = "${element(var.vpc-public-cidrs, count.index)}"
  }
}

data "template_file" "oidc-apiserver-conf" {
  count = "${var.oidc-issuer-url == "" ? 0 : 1}"

  template = <<EOF
    oidcCAFile: ${var.oidc-ca-file}
    oidcClientID: ${var.oidc-client-id}
    oidcGroupsClaim: ${var.oidc-groups-claim}
    oidcIssuerURL: ${var.oidc-issuer-url}
    oidcUsernameClaim: ${var.oidc-username-claim}
EOF
}

data "template_file" "apiserver-runtime-configs" {
  count = "${length(var.apiserver-runtime-flags)}"

  template = "      ${element(keys(var.apiserver-runtime-flags), count.index)}: '${element(values(var.apiserver-runtime-flags), count.index)}'"
}

data "template_file" "hooks" {
  count = "${length(var.hooks)}"

  template = <<EOF
${element(var.hooks, count.index)}
EOF
}
