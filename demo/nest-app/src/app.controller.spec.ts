import { Test, TestingModule } from '@nestjs/testing';
import { AppController } from './app.controller';

describe('AppController', () => {
  let appController: AppController;

  beforeEach(async () => {
    const app: TestingModule = await Test.createTestingModule({
      controllers: [AppController],
    }).compile();

    appController = app.get<AppController>(AppController);
  });

  describe('root', () => {
    it('should return secret metadata', () => {
      process.env.db_username = 'testuser';
      process.env.db_password = 'testpass';

      const result = appController.getSecretMetadata();

      expect(result).toEqual({
        message: 'Vault secrets injected successfully',
        secrets: [
          { key: 'db_username', present: true, length: 8 },
          { key: 'db_password', present: true, length: 8 },
        ],
      });

      delete process.env.db_username;
      delete process.env.db_password;
    });
  });
});
