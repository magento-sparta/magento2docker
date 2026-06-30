ARG M2D_ENABLE_BLACKFIRE='no'

FROM busybox:1.36 as m2d_blackfire_no
CMD ["tail", "-f", "/dev/null"]

FROM blackfire/blackfire AS m2d_blackfire_yes

FROM m2d_blackfire_${M2D_ENABLE_BLACKFIRE} AS m2d_blackfire
