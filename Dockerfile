# ─────────────────────────────────────────────────────────────────────────────
# Odoo 18 Enterprise — local image (not pushed to Docker Hub)
#
# Custom modules and enterprise are bind-mounted at runtime via
# docker-compose.yml, so this image only carries the base + config.
# Adding/editing modules in erp-odoo-arm never requires a rebuild.
# ─────────────────────────────────────────────────────────────────────────────
FROM odoo:18.0

USER root

COPY conf/odoo.conf /etc/odoo/odoo.conf

USER odoo
