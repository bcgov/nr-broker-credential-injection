import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  await app.listen(3600);
  console.log('NestJS Application is running on: http://localhost:3600');
}
bootstrap();
