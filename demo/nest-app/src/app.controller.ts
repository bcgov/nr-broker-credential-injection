import { Controller, Get } from '@nestjs/common';

const VAULT_SECRET_KEYS = ['db_username', 'db_password'];

@Controller()
export class AppController {
  @Get('/')
  getSecretMetadata(): Record<string, unknown> {
    const secrets = VAULT_SECRET_KEYS.map((key) => ({
      key,
      present: process.env[key] != null,
      length: process.env[key]?.length ?? 0,
    }));

    return {
      message: 'Vault secrets injected successfully',
      secrets,
    };
  }
}
