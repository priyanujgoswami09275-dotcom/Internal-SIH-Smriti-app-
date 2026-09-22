"""Notification system — UserDeviceToken + NotificationDelivery (2026-09-07)."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0004_notifications'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'user_device_tokens',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('fcm_token', sa.String(length=500), nullable=True),
        sa.Column('phone', sa.String(length=50), nullable=True),
        sa.Column('platform', sa.String(length=20), server_default='android', nullable=False),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_user_device_tokens_user_id', 'user_device_tokens', ['user_id'], unique=False)

    op.create_table(
        'notification_deliveries',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('provider', sa.String(length=20), nullable=False),
        sa.Column('kind', sa.Enum('reprompt', 'alert', name='notificationkindenum'), nullable=False),
        sa.Column('event_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('recipient_user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id'), nullable=True),
        sa.Column('address', sa.String(length=500), nullable=True),
        sa.Column('status', sa.Enum('sent', 'failed', name='notificationdeliverystatusenum'), server_default='sent', nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_notification_deliveries_provider', 'notification_deliveries', ['provider'], unique=False)
    op.create_index('ix_notification_deliveries_recipient_user_id', 'notification_deliveries', ['recipient_user_id'], unique=False)


def downgrade():
    op.drop_index('ix_notification_deliveries_recipient_user_id', table_name='notification_deliveries')
    op.drop_index('ix_notification_deliveries_provider', table_name='notification_deliveries')
    op.drop_table('notification_deliveries')
    op.drop_index('ix_user_device_tokens_user_id', table_name='user_device_tokens')
    op.drop_table('user_device_tokens')
    # The inline enums are created with the tables; without these drops they
    # orphan in PG and the re-upgrade fails with DuplicateObject.
    op.execute("DROP TYPE IF EXISTS notificationkindenum")
    op.execute("DROP TYPE IF EXISTS notificationdeliverystatusenum")
