//+------------------------------------------------------------------+
//|                                                      Reforma.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "2.00"
#property description "Expert Advisor Profissional com RSI, Grid Trading, Trailing Stop e Gestão de Risco Avançada"

#include <Controls\Dialog.mqh>
#include <Controls\Funçoes.mqh>
#include <Trade\Trade.mqh>

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

enum ENUM_RISK_MODE {
   RISK_FIXED = 0,      // Risco Fixo
   RISK_PERCENT = 1,    // Risco Percentual
   RISK_MARTINGALE = 2  // Martingale
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "=== Configurações de Trading ==="
input double trade_volume = 0.01;    // Volume
input int alvo = 100;               // Take Profit (points)
input int stop_loss = 100;          // Stop Loss (points)
input int magic_number = 123456;    // Magic Number
input ENUM_RISK_MODE risk_mode = RISK_FIXED; // Modo de Risco

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
input double max_risk_percent = 2.0; // Risco Máximo (% da conta)

input group "=== Configurações de Alerta ==="
input bool enable_alerts = true;    // Ativar Alertas
input bool enable_email = false;    // Ativar Email
input bool enable_push = false;     // Ativar Push Notifications

input group "=== Configurações de Otimização ==="
input bool enable_backtest = false; // Modo Backtest
input int max_spread = 50;          // Spread Máximo (points)
input bool check_news = true;       // Verificar Notícias
input int news_before = 30;         // Minutos Antes da Notícia
input int news_after = 30;          // Minutos Após a Notícia

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int rsiHandle = INVALID_HANDLE;
double point;
datetime lastBar = 0;
double dailyProfit = 0.0;
datetime lastDayReset = 0;
CTrade trade;
bool isNewsTime = false;
datetime lastNewsCheck = 0;

// Statistics
struct STATS {
   int total_trades;
   int winning_trades;
   int losing_trades;
   double total_profit;
   double max_profit;
   double max_loss;
   double win_rate;
   datetime start_time;
};

STATS stats;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize point value
   point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   // Initialize trade object
   trade.SetExpertMagicNumber(magic_number);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   
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
   
   // Initialize statistics
   InitializeStats();
   
   // Reset daily profit
   ResetDailyProfit();
   
   Print("=== REFORMA EA v2.00 ===");
   Print("Símbolo: ", _Symbol, " | Volume: ", trade_volume, " | Magic: ", magic_number);
   Print("Modo de Risco: ", EnumToString(risk_mode));
   Print("Grid Trading: ", (usar_grid == GRID_SIM ? "Ativo" : "Inativo"));
   Print("Trailing Stop: ", (usar_trailing == TRAIL_SIM ? "Ativo" : "Inativo"));
   Print("RSI: ", (ativa_rsi ? "Ativo" : "Inativo"));
   
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
   
   // Print final statistics
   PrintFinalStats();
   
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
   
   // Check spread
   if(!CheckSpread()) {
      return;
   }
   
   // Check news time
   if(check_news && IsNewsTime()) {
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
   
   if(max_risk_percent <= 0 || max_risk_percent > 10) {
      Print("Erro: Risco percentual deve estar entre 0.1% e 10%");
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
//| Check spread                                                      |
//+------------------------------------------------------------------+
bool CheckSpread()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > max_spread) {
      if(enable_alerts) {
         Alert("Spread muito alto: ", spread, " points");
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if it's news time                                          |
//+------------------------------------------------------------------+
bool IsNewsTime()
{
   // Simple news time check (you can implement more sophisticated news checking)
   datetime currentTime = TimeCurrent();
   int currentHour = TimeHour(currentTime);
   
   // Avoid trading during major news times (example: 8:00-9:00 and 14:00-15:00)
   if((currentHour >= 8 && currentHour < 9) || (currentHour >= 14 && currentHour < 15)) {
      if(!isNewsTime) {
         isNewsTime = true;
         if(enable_alerts) {
            Print("Período de notícias - Trading pausado");
         }
      }
      return true;
   } else {
      if(isNewsTime) {
         isNewsTime = false;
         if(enable_alerts) {
            Print("Período de notícias finalizado - Trading retomado");
         }
      }
      return false;
   }
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk mode                       |
//+------------------------------------------------------------------+
double CalculatePositionSize()
{
   double size = trade_volume;
   
   switch(risk_mode) {
      case RISK_PERCENT:
         double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskAmount = accountBalance * (max_risk_percent / 100.0);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         size = riskAmount / (stop_loss * tickValue);
         break;
         
      case RISK_MARTINGALE:
         int totalPositions = QuantidadeDePosicoesTotal(_Symbol);
         if(totalPositions > 0) {
            size = trade_volume * MathPow(multiplicador, totalPositions);
         }
         break;
   }
   
   // Ensure minimum and maximum position size
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   size = MathMax(minVolume, MathMin(maxVolume, size));
   
   return NormalizeDouble(size, 2);
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
   
   double positionSize = CalculatePositionSize();
   
   if(ativa_rsi) {
      ExecuteRSITrading(rsiValues, positionSize);
   } else {
      ExecutePatternTrading(positionSize);
   }
}

//+------------------------------------------------------------------+
//| Execute RSI-based trading                                         |
//+------------------------------------------------------------------+
void ExecuteRSITrading(const double &rsiValues[], double positionSize)
{
   // Sell signal: RSI above overbought level with bearish pattern
   if(rsiValues[0] > nivel_sobrecompra && 
      vela_de_baixa(1) && vela_de_auta(2) && vela_de_auta(3) && vela_de_auta(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Venda_a_mercado(positionSize, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Venda executada - RSI sobrecomprado: ", rsiValues[0], " | Volume: ", positionSize);
         UpdateStats(true, 0);
         SendAlert("Venda executada", "RSI sobrecomprado: " + DoubleToString(rsiValues[0], 2));
      }
   }
   
   // Buy signal: RSI below oversold level with bullish pattern
   if(rsiValues[0] < nivel_sobrevenda && 
      vela_de_auta(1) && vela_de_baixa(2) && vela_de_baixa(3) && vela_de_baixa(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Compra_a_mercado(positionSize, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Compra executada - RSI sobrevendido: ", rsiValues[0], " | Volume: ", positionSize);
         UpdateStats(true, 0);
         SendAlert("Compra executada", "RSI sobrevendido: " + DoubleToString(rsiValues[0], 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Execute pattern-based trading                                     |
//+------------------------------------------------------------------+
void ExecutePatternTrading(double positionSize)
{
   // Sell signal: bearish pattern
   if(vela_de_baixa(1) && vela_de_auta(2) && vela_de_auta(3) && vela_de_auta(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Venda_a_mercado(positionSize, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Venda executada - Padrão de baixa | Volume: ", positionSize);
         UpdateStats(true, 0);
         SendAlert("Venda executada", "Padrão de baixa identificado");
      }
   }
   
   // Buy signal: bullish pattern
   if(vela_de_auta(1) && vela_de_baixa(2) && vela_de_baixa(3) && vela_de_baixa(4) && 
      QuantidadeDePosicoesTotal(_Symbol) == 0) {
      
      if(Compra_a_mercado(positionSize, _Symbol, stop_loss, alvo, true, true, true, magic_number)) {
         Print("Compra executada - Padrão de alta | Volume: ", positionSize);
         UpdateStats(true, 0);
         SendAlert("Compra executada", "Padrão de alta identificado");
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
            UpdateStats(false, totalProfit);
            SendAlert("Grid fechado", "Lucro: " + DoubleToString(totalProfit, 2));
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
//| Initialize statistics                                              |
//+------------------------------------------------------------------+
void InitializeStats()
{
   stats.total_trades = 0;
   stats.winning_trades = 0;
   stats.losing_trades = 0;
   stats.total_profit = 0.0;
   stats.max_profit = 0.0;
   stats.max_loss = 0.0;
   stats.win_rate = 0.0;
   stats.start_time = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Update statistics                                                 |
//+------------------------------------------------------------------+
void UpdateStats(bool isNewTrade, double profit)
{
   if(isNewTrade) {
      stats.total_trades++;
   } else {
      stats.total_profit += profit;
      
      if(profit > 0) {
         stats.winning_trades++;
         if(profit > stats.max_profit) stats.max_profit = profit;
      } else {
         stats.losing_trades++;
         if(profit < stats.max_loss) stats.max_loss = profit;
      }
      
      if(stats.total_trades > 0) {
         stats.win_rate = (double)stats.winning_trades / stats.total_trades * 100.0;
      }
   }
}

//+------------------------------------------------------------------+
//| Print final statistics                                            |
//+------------------------------------------------------------------+
void PrintFinalStats()
{
   Print("=== ESTATÍSTICAS FINAIS ===");
   Print("Total de Trades: ", stats.total_trades);
   Print("Trades Vencedores: ", stats.winning_trades);
   Print("Trades Perdedores: ", stats.losing_trades);
   Print("Taxa de Acerto: ", DoubleToString(stats.win_rate, 2), "%");
   Print("Lucro Total: ", DoubleToString(stats.total_profit, 2));
   Print("Maior Lucro: ", DoubleToString(stats.max_profit, 2));
   Print("Maior Perda: ", DoubleToString(stats.max_loss, 2));
   Print("Tempo de Execução: ", TimeToString(TimeCurrent() - stats.start_time));
}

//+------------------------------------------------------------------+
//| Send alert                                                        |
//+------------------------------------------------------------------+
void SendAlert(string title, string message)
{
   if(!enable_alerts) return;
   
   string fullMessage = "REFORMA EA - " + title + ": " + message;
   
   if(enable_email) {
      SendMail("REFORMA EA Alert", fullMessage);
   }
   
   if(enable_push) {
      SendNotification(fullMessage);
   }
   
   Alert(fullMessage);
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
      SendAlert("Limite Diário", "Perda máxima atingida: " + DoubleToString(currentProfit, 2));
      return false;
   }
   
   // Check daily profit limit
   if(currentProfit >= max_daily_profit) {
      Print("Limite de lucro diário atingido: ", currentProfit);
      SendAlert("Limite Diário", "Lucro máximo atingido: " + DoubleToString(currentProfit, 2));
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
   comment += "=== REFORMA EA v2.00 ===\n";
   comment += "Símbolo: " + _Symbol + "\n";
   comment += "Volume: " + DoubleToString(CalculatePositionSize(), 2) + "\n";
   comment += "Posições: " + QuantidadeDePosicoesTotal(_Symbol) + "\n";
   comment += "Compras: " + QuantidadeDePosicoesDecompra(_Symbol) + "\n";
   comment += "Vendas: " + QuantidadeDePosicoesDeVenda(_Symbol) + "\n";
   comment += "Lucro: " + DoubleToString(CalculateOpenPositionsProfit(), 2) + "\n";
   comment += "Lucro Diário: " + DoubleToString(dailyProfit, 2) + "\n";
   comment += "Taxa de Acerto: " + DoubleToString(stats.win_rate, 1) + "%\n";
   comment += "Grid: " + (usar_grid == GRID_SIM ? "Ativo" : "Inativo") + "\n";
   comment += "Trailing: " + (usar_trailing == TRAIL_SIM ? "Ativo" : "Inativo") + "\n";
   comment += "RSI: " + (ativa_rsi ? "Ativo" : "Inativo") + "\n";
   comment += "Risco: " + EnumToString(risk_mode) + "\n";
   comment += "Spread: " + IntegerToString(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
   
   Comment(comment);
}

//+------------------------------------------------------------------+