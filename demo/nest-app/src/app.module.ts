import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
//import { VaultService } from './vault.service';
import { AppService } from './app.service';

@Module({
  imports: [],
  controllers: [AppController],
  providers: [AppService],
  //  providers: [AppService, VaultService],
})
export class AppModule {}
