//+------------------------------------------------------------------+
//|                                                      Reforma.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Controls\Dialog.mqh>
#include <Controls\Funçoes.mqh>

enum grad {
   GRID_SIM = 0,    // Sim
   GRID_NAO = 1     // Não
};

enum traligg {
   TRAIL_NAO = 0,   // Não
   TRAIL_SIM = 1    // Sim
};

enum ENUM_TIPO_MA {
   SMA = 0,    // Média Móvel Simples
   EMA = 1,    // Média Móvel Exponencial
   SMMA = 2,   // Média Móvel Suavizada
   LWMA = 3    // Média Móvel Ponderada
};

// Input parameters
input group "Trade Settings"
input double trade_volume = 0.01;    // Volume
input int alvo = 100;               // Take Profit (points)
input int stop_loss = 100;          // Stop Loss (points)

input group "Trailing Stop Settings"
input traligg usar_trailing = TRAIL_SIM; // Usar Trailing Stop?
input int trailing_start = 100;     // Trailing Start (points)
input int trailing_space = 200;     // Trailing Space (points)



input group "Grid Settings"
input grad usar_grid = GRID_SIM;    // Usar Grid?
input int multiplicador = 2;        // Multiplicador de Volume
input int distancia_grid = 100;     // Distância Grid (points)
input int quantidade = 10;          // Quantidade de Ordens Grid
input double saida_lucro =  10.00;
input double saida_prejuizo = - 10.00;

input group "Indicator Settings"
input bool ativa_rsi = true;        // Ativar RSI
input ENUM_TIPO_MA tipo_media = EMA; // Tipo de Média Móvel
input int periodo_rsi = 16;         // Período RSI
input int nivel_sobrevenda = 30;    // Nível de Sobrevenda
input int nivel_sobrecompra = 70;   // Nível de Sobrecompra


double point;
int rsiHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{


// Initialize RSI
   if(ativa_rsi) {
      rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, periodo_rsi, tipo_media);
      ChartIndicatorAdd(0,1,rsiHandle);
      if(rsiHandle == INVALID_HANDLE) {
         Print("Failed to create RSI indicator");
         return(INIT_FAILED);
      }
   }



   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE)
      IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{

// Get RSI value
   double rsiValue[];
   ArraySetAsSeries(rsiValue, true);
   if(ativa_rsi && CopyBuffer(rsiHandle, 0, 0, 2, rsiValue) < 2) {
      Print("Failed to copy RSI buffer");
      return;
   }

// Check for new bar
   static datetime lastBar;
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(lastBar != currentBar) {
      lastBar = currentBar;
      
      // Trading logic based on RSI
      if(ativa_rsi) {
         // Sell signal: RSI above overbought level with bearish pattern
         if(rsiValue[0] > nivel_sobrecompra && vela_de_baixa(1) && vela_de_auta(2) && vela_de_auta(3) && vela_de_auta(4) && QuantidadeDePosicoesTotal(_Symbol) == 0) {
            Venda_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, 123456);
            Print("Venda executada - RSI sobrecomprado");
         }

         // Buy signal: RSI below oversold level with bullish pattern
         if(rsiValue[0] < nivel_sobrevenda && vela_de_auta(1) && vela_de_baixa(2) && vela_de_baixa(3) && vela_de_baixa(4) && QuantidadeDePosicoesTotal(_Symbol) == 0) {
            Compra_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, 123456);
            Print("Compra executada - RSI sobrevendido");
         }
      }

      // Trading logic without RSI
      if(!ativa_rsi) {
         // Sell signal: bearish pattern
         if(vela_de_baixa(1) && vela_de_auta(2) && vela_de_auta(3) && vela_de_auta(4) && QuantidadeDePosicoesTotal(_Symbol) == 0) {
            Venda_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, 123456);
            Print("Venda executada - Padrão de baixa");
         }
         
         // Buy signal: bullish pattern
         if(vela_de_auta(1) && vela_de_baixa(2) && vela_de_baixa(3) && vela_de_baixa(4) && QuantidadeDePosicoesTotal(_Symbol) == 0) {
            Compra_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, 123456);
            Print("Compra executada - Padrão de alta");
         }
      }
   }

   // Grid trading logic
   if(usar_grid == GRID_SIM) {
      Comment("Posições de Compra: " + QuantidadeDePosicoesDecompra(_Symbol));
      
      if(QuantidadeDePosicoesDecompra(_Symbol) == 0 && QuantidadeDePosicoesDeVenda(_Symbol) > 0) {
         grideVenda(multiplicador, distancia_grid, quantidade);
      }
      
      if(QuantidadeDePosicoesDeVenda(_Symbol) == 0 && QuantidadeDePosicoesDecompra(_Symbol) > 0) {
         grideCompra(multiplicador, distancia_grid, quantidade);
      }
      
      double profit = CalculateOpenPositionsProfit();
      Comment("Lucro Total: " + profit);
      
      if((profit >= saida_lucro || profit <= saida_prejuizo) && QuantidadeDePosicoesTotal(_Symbol) > 1) {
         ApagarTodasAsPosiçoes(_Symbol);
         Print("Todas as posições fechadas - Lucro: " + profit);
      }
   }

   // Trailing stop logic
   if(usar_trailing == TRAIL_SIM) {
      if(QuantidadeDePosicoesTotal(_Symbol) == 1) {
         TrailingStopGlobal(trailing_space, trailing_start);
      }
   }
}


//+------------------------------------------------------------------+