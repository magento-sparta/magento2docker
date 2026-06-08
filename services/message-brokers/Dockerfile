ARG M2D_ENABLE_MESSAGE_BROKER='no'
ARG M2D_MESSAGE_BROKER_VENDOR='rabbitmq'
ARG M2D_MESSAGE_BROKER_VERSION='3.8'

FROM scratch as m2d_message_broker_no
COPY tools/dummy/dummy ./
CMD ["/dummy"]

FROM rabbitmq:3.8-management AS m2d_message_broker_rabbitmq_3.8
FROM rabbitmq:3.9-management AS m2d_message_broker_rabbitmq_3.9
FROM rabbitmq:3.11-management AS m2d_message_broker_rabbitmq_3.11
FROM rabbitmq:3.12-management AS m2d_message_broker_rabbitmq_3.12
FROM rabbitmq:3.13-management AS m2d_message_broker_rabbitmq_3.13

FROM m2d_message_broker_${M2D_MESSAGE_BROKER_VENDOR}_${M2D_MESSAGE_BROKER_VERSION} AS m2d_message_broker_yes

FROM m2d_message_broker_${M2D_ENABLE_MESSAGE_BROKER} AS m2d_message_broker
