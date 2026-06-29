## set the default value for the argument if not defined
ARG M2D_ENABLE_MAILCATCHER='no'

## prepare a dummy container for the "no" option
FROM busybox:1.36 as m2d_mailcatcher_no
CMD ["tail", "-f", "/dev/null"]

## prepare the actual Mailcatcher container for the "yes" option
FROM dockage/mailcatcher AS m2d_mailcatcher_yes

## build target container from mailcatcher_yes or mailcatcher_no based on value from M2D_ENABLE_MAILCATCHER argument
FROM m2d_mailcatcher_${M2D_ENABLE_MAILCATCHER} AS m2d_mailcatcher
