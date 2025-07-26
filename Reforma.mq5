//+------------------------------------------------------------------+
//|                                                      Reforma.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.01"
#property description "Expert Advisor com RSI, Grid Trading e Trailing Stop"

#include <Controls\Dialog.mqh>
#include <Controls\Funçoes.mqh>

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ENUM_GRID_MODE {
   GRID_SIM = 0,    // Sim
   GRID_NAO = 1     // Não
};

enum ENUM_TRAILING_MODE {
   TRAIL_NAO = 0,   // Não
   TRAIL_SIM = 1    // Sim
};

enum ENUM_TIPO_MA {
   SMA = 0,    // Média Móvel Simples
   EMA = 1,    // Média Móvel Exponencial
   SMMA = 2,   // Média Móvel Suavizada
   LWMA = 3    // Média Móvel Ponderada
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Configurações de Trading ==="
input double trade_volume = 0.01;    // Volume
input int alvo = 100;               // Take Profit (points)
input int stop_loss = 100;          // Stop Loss (points)
input int magic_number = 123456;    // Magic Number

input group "=== Configurações de Trailing Stop ==="
input ENUM_TRAILING_MODE usar_trailing = TRAIL_SIM; // Usar Trailing Stop?
input int trailing_start = 100;     // Trailing Start (points)
input int trailing_space = 200;     // Trailing Space (points)

input group "=== Configurações de Grid Trading ==="
input ENUM_GRID_MODE usar_grid = GRID_SIM;    // Usar Grid?
input int multiplicador = 2;        // Multiplicador de Volume
input int distancia_grid = 100;     // Distância Grid (points)
input int quantidade = 10;          // Quantidade de Ordens Grid
input double saida_lucro = 10.00;   // Saída por Lucro
input double saida_prejuizo = -10.00; // Saída por Prejuízo

input group "=== Configurações do Indicador RSI ==="
input bool ativa_rsi = true;        // Ativar RSI
input ENUM_TIPO_MA tipo_media = EMA; // Tipo de Média Móvel
input int periodo_rsi = 16;         // Período RSI
input int nivel_sobrevenda = 30;    // Nível de Sobrevenda
input int nivel_sobrecompra = 70;   // Nível de Sobrecompra

input group "=== Configurações de Segurança ==="
input int max_positions = 50;       // Máximo de Posições
input double max_daily_loss = -100.0; // Perda Máxima Diária
input double max_daily_profit = 500.0; // Lucro Máximo Diário

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int rsiHandle = INVALID_HANDLE;
double point;
datetime lastBar = 0;
double dailyProfit = 0.0;
datetime lastDayReset = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize point value
   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Validate input parameters
   if(!ValidateInputs()) {
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   // Initialize RSI indicator
   if(ativa_rsi) {
      rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, periodo_rsi, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE) {
         Print("Erro: Falha ao criar indicador RSI");
         return(INIT_FAILED);
      }
      
      // Add indicator to chart
      if(!ChartIndicatorAdd(0, 1, rsiHandle)) {
         Print("Aviso: Não foi possível adicionar RSI ao gráfico");
      }
   }
   
   // Reset daily profit
   ResetDailyProfit();
   
   Print("Expert Advisor inicializado com sucesso");
   Print("Símbolo: ", _Symbol, " | Volume: ", trade_volume, " | Magic: ", magic_number);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(rsiHandle != INVALID_HANDLE) {
      IndicatorRelease(rsiHandle);
   }
   
   Comment("");
   Print("Expert Advisor finalizado. Razão: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for new day and reset daily profit
   CheckAndResetDailyProfit();
   
   // Check daily limits
   if(!CheckDailyLimits()) {
      return;
   }
   
   // Get RSI values if enabled
   double rsiValue[3] = {0};
   if(ativa_rsi) {
      if(!GetRSIValues(rsiValue)) {
         return;
      }
   }
   
   // Check for new bar
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(lastBar != currentBar) {
      lastBar = currentBar;
      
      // Execute trading logic
      ExecuteTradingLogic(rsiValue);
   }
   
   // Execute grid logic
   if(usar_grid == GRID_SIM) {
      ExecuteGridLogic();
   }
   
   // Execute trailing stop
   if(usar_trailing == TRAIL_SIM) {
      ExecuteTrailingStop();
   }
   
   // Update comment
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Validate input parameters                                         |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if(trade_volume <= 0) {
      Print("Erro: Volume deve ser maior que zero");
      return false;
   }
   
   if(alvo <= 0 || stop_loss <= 0) {
      Print("Erro: Take Profit e Stop Loss devem ser maiores que zero");
      return false;
   }
   
   if(periodo_rsi <= 0) {
      Print("Erro: Período RSI deve ser maior que zero");
      return false;
   }
   
   if(nivel_sobrevenda >= nivel_sobrecompra) {
      Print("Erro: Nível de sobrevenda deve ser menor que sobrecompra");
      return false;
   }
   
   if(multiplicador <= 0 || quantidade <= 0) {
      Print("Erro: Multiplicador e quantidade devem ser maiores que zero");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get RSI values                                                    |
//+------------------------------------------------------------------+
bool GetRSIValues(double &rsiValues[])
{
   ArraySetAsSeries(rsiValues, true);
   if(CopyBuffer(rsiHandle, 0, 0, 3, rsiValues) < 3) {
      Print("Erro: Falha ao copiar dados do RSI");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Execute trading logic                                             |
//+------------------------------------------------------------------+
void ExecuteTradingLogic(const double &rsiValues[])
{
   // Check if we can open new positions
   if(QuantidadeDePosicoesTotal(_Symbol) >= max_positions) {
      return;
   }
   
   if(ativa_rsi) {
      ExecuteRSITrading(rsiValues);
   } else {
      ExecutePatternTrading();
   }
}

//+------------------------------------------------------------------+
//| Execute RSI-based trading                                         |
//+------------------------------------------------------------------+
void ExecuteRSITrading(const double &rsiValues[])
{
   // Sell signal: RSI above overbought level with bearish pattern
   if(rsiValues[0] > nivel_sobrecompra && 
      vela_de_baixa(1) && vela_de_auta(2) && vela_de_auta(3) && vela_de_auta(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Venda_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Venda executada - RSI sobrecomprado: ", rsiValues[0]);
      }
   }
   
   // Buy signal: RSI below oversold level with bullish pattern
   if(rsiValues[0] < nivel_sobrevenda && 
      vela_de_auta(1) && vela_de_baixa(2) && vela_de_baixa(3) && vela_de_baixa(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Compra_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Compra executada - RSI sobrevendido: ", rsiValues[0]);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute pattern-based trading                                     |
//+------------------------------------------------------------------+
void ExecutePatternTrading()
{
   // Sell signal: bearish pattern
   if(vela_de_baixa(1) && vela_de_auta(2) && vela_de_auta(3) && vela_de_auta(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Venda_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Venda executada - Padrão de baixa");
      }
   }
   
   // Buy signal: bullish pattern
   if(vela_de_auta(1) && vela_de_baixa(2) && vela_de_baixa(3) && vela_de_baixa(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Compra_a_mercado(trade_volume, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Compra executada - Padrão de alta");
      }
   }
}

//+------------------------------------------------------------------+
//| Execute grid logic                                                |
//+------------------------------------------------------------------+
void ExecuteGridLogic()
{
   int buyPositions = QuantidadeDePosicoesDecompra(_Symbol);
   int sellPositions = QuantidadeDePosicoesDeVenda(_Symbol);
   
   // Create sell grid if we have buy positions but no sell positions
   if(buyPositions > 0 && sellPositions == 0) {
      grideVenda(multiplicador, distancia_grid, quantidade);
   }
   
   // Create buy grid if we have sell positions but no buy positions
   if(sellPositions > 0 && buyPositions == 0) {
      grideCompra(multiplicador, distancia_grid, quantidade);
   }
   
   // Check profit/loss exit conditions
   double totalProfit = CalculateOpenPositionsProfit();
   if(QuantidadeDePosicoesTotal(_Symbol) > 1) {
      if(totalProfit >= saida_lucro || totalProfit <= saida_prejuizo) {
         if(ApagarTodasAsPosiçoes(_Symbol)) {
            Print("Todas as posições fechadas - Lucro: ", totalProfit);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute trailing stop                                             |
//+------------------------------------------------------------------+
void ExecuteTrailingStop()
{
   if(QuantidadeDePosicoesTotal(_Symbol) == 1) {
      TrailingStopGlobal(trailing_space, trailing_start);
   }
}

//+------------------------------------------------------------------+
//| Check and reset daily profit                                      |
//+------------------------------------------------------------------+
void CheckAndResetDailyProfit()
{
   datetime currentDay = TimeCurrent();
   if(TimeDay(currentDay) != TimeDay(lastDayReset)) {
      ResetDailyProfit();
   }
}

//+------------------------------------------------------------------+
//| Reset daily profit                                                |
//+------------------------------------------------------------------+
void ResetDailyProfit()
{
   dailyProfit = 0.0;
   lastDayReset = TimeCurrent();
   Print("Lucro diário resetado");
}

//+------------------------------------------------------------------+
//| Check daily limits                                                |
//+------------------------------------------------------------------+
bool CheckDailyLimits()
{
   double currentProfit = CalculateOpenPositionsProfit();
   
   // Check daily loss limit
   if(currentProfit <= max_daily_loss) {
      Print("Limite de perda diária atingido: ", currentProfit);
      return false;
   }
   
   // Check daily profit limit
   if(currentProfit >= max_daily_profit) {
      Print("Limite de lucro diário atingido: ", currentProfit);
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Update comment on chart                                           |
//+------------------------------------------------------------------+
void UpdateComment()
{
   string comment = "";
   comment += "=== REFORMA EA ===\n";
   comment += "Símbolo: " + _Symbol + "\n";
   comment += "Volume: " + DoubleToString(trade_volume, 2) + "\n";
   comment += "Posições: " + QuantidadeDePosicoesTotal(_Symbol) + "\n";
   comment += "Compras: " + QuantidadeDePosicoesDecompra(_Symbol) + "\n";
   comment += "Vendas: " + QuantidadeDePosicoesDeVenda(_Symbol) + "\n";
   comment += "Lucro: " + DoubleToString(CalculateOpenPositionsProfit(), 2) + "\n";
   comment += "Lucro Diário: " + DoubleToString(dailyProfit, 2) + "\n";
   comment += "Grid: " + (usar_grid == GRID_SIM ? "Ativo" : "Inativo") + "\n";
   comment += "Trailing: " + (usar_trailing == TRAIL_SIM ? "Ativo" : "Inativo") + "\n";
   comment += "RSI: " + (ativa_rsi ? "Ativo" : "Inativo");
   
   Comment(comment);
}

//+------------------------------------------------------------------+