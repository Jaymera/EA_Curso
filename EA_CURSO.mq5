//+------------------------------------------------------------------+
//|                                                     EA CURSO.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include <Modulos_EA.mqh>

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

enum LIGA
  {
   SIM, //Sim
   NAO  //Não
  };
  
enum ESTRATEGIA_ENTRADA
  {
   APENAS_MM,   //Apenas Médias Móveis
   APENAS_MACD, //Apenas MACD
   MM_E_MACD    //Médias mais MACD
  };
  
enum LIGA_TS
  {
   SIM_TS, //Sim
   NAO_TS  //Não
  };
  
enum LIGA_PARCIAL
  {
   SIM_PARCIAL, //Sim
   NAO_PARCIAL  //Não
  };
  
sinput string s0; //----Estratégia de Entrada----
input string               ativoOperacao = "WINM22";     //Ativo de Operação
input ESTRATEGIA_ENTRADA   estrategia    = MM_E_MACD;    //Estratégia de Entrada Trader
input LIGA                 liga_breakeven= NAO;          //Liga Breakeven
input double               StartBE       = 100;          //Iniciar Breakeven
input double               PointBE       = 10;           //Pontos do Breakeven
input LIGA_TS              liga_train    = SIM_TS;       //Liga TS
input double               StartTS       = 100;          //Inicia TS
//input double             StepTS        = 60;           //Step TS
input LIGA_PARCIAL         liga_par      = SIM_PARCIAL;  //Liga Parcial
input int                  nContrato     = 1;            //Número de contrato
input double               StartParcial  = 75;           //Iniciar Parcial

sinput string s1; //----Médias Móveis----
input int mm_rapida_periodo               = 8;              //Periodo Média Rápida
input int mm_lenta_periodo                = 200;            //Periodo Média Lenta
input ENUM_TIMEFRAMES   mm_tempo_grafico  = PERIOD_CURRENT; //Tempo Gráfico
input ENUM_MA_METHOD    mm_metodo         = MODE_EMA;       //Método
input ENUM_APPLIED_PRICE mm_preco         = PRICE_CLOSE;    //Preço Aplicado

sinput string s2; //----MACD----
input ENUM_APPLIED_PRICE TIPOPRECOMACD    = PRICE_CLOSE;    //Tipo Preço
input int MARAPIDAMACD = 17;                                //MACD Rápida
input int MALENTAMACD = 34;                                 //MACD Lento
input int PERIODOMACD = 8;                                  //MACD Período

sinput string s3; //----Financeiro----
input double num_lots            = 2;     //Números de Lotes
input double pts_TK              = 500;   //TAKE PROFIT
input double pts_SL              = 250;   //Stop LOSS
input double lucro_max_dia       = 200;   //Lucro máx díario
input double perda_max_dia       = 200;   //Perda máx díaria

sinput string s4; //----Financeiro----
input string hora_limite_fecha_op   = "17:30"; //Horário Limite Fechar Posição
input string inicio_op              = "09:05"; //Horáriopara iniciar operações
input string fim_op                 = "17:00"; //Horário para finalizar operações

//+------------------------------------------------------------------+
//|             Variáveis                                                     |
//+------------------------------------------------------------------+
//--- Médias Móveis
//--- RÁPIDA
int mm_rapida_handle;
double mm_rapida_buffer[];

//---LENTA
int mm_lenta_handle;
double mm_lenta_buffer[];

//---MACD
int macd_handle;
double macd_buffer[];

//--- Indice e dolar
double SL, TK;

//--- Ativo para operar
string ativoOp;

//--- magic
int magic_magico = 123456;

//--- velas e tick
MqlRates velas[];
MqlTick tick;


int OnInit()
  {
//--- Controle de vencimento
   vencimento();
   
   ativoOp           = (ativoOperacao==""?_Symbol:ativoOperacao);
   
   macd_handle       = iMACD(_Symbol,_Period,MARAPIDAMACD,MALENTAMACD,PERIODOMACD,PRICE_CLOSE);
   
   mm_rapida_handle  = iMA(_Symbol,mm_tempo_grafico,mm_rapida_periodo,0,mm_metodo,mm_preco);
   mm_lenta_handle   = iMA(_Symbol,mm_tempo_grafico,mm_lenta_periodo,0,mm_metodo,mm_preco);
   
   if(mm_rapida_handle < 0 || mm_lenta_handle < 0 || macd_handle < 0)
     {
      Alert("Erro ao tentar criar handles para o indicador - erro: ",GetLastError());
      return(-1);
     }
     
  CopyRates(_Symbol,_Period,0,4,velas);
  ArraySetAsSeries(velas,true);
  
  ChartIndicatorAdd(0,0,mm_rapida_handle);
  ChartIndicatorAdd(0,0,mm_lenta_handle);
  ChartIndicatorAdd(0,1,macd_handle);
  //--- Rodar no indice e no dolar
  if(_Digits == 3)
    {
     SL = pts_SL*1000;
     TK = pts_TK*1000;
    }else
       {
        SL = pts_SL;
        TK = pts_TK;
       }
  
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   IndicatorRelease(mm_rapida_handle);
   IndicatorRelease(mm_lenta_handle);
   IndicatorRelease(macd_handle);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---Criando a base de dados
   CopyBuffer(macd_handle,0,0,4,macd_buffer);
   CopyBuffer(mm_rapida_handle,0,0,4,mm_rapida_buffer);
   CopyBuffer(mm_lenta_handle,0,0,4,mm_lenta_buffer);
   
//--- Alimentar os Buffers das velas
   CopyRates(_Symbol,_Period,0,4,velas);
   ArraySetAsSeries(velas,true);
   
//--- Ordenar os vetores de dados
   ArraySetAsSeries(macd_buffer,true);
   ArraySetAsSeries(mm_rapida_buffer,true);
   ArraySetAsSeries(mm_lenta_buffer,true);
   
//--- Alimentar com dados do tick
   SymbolInfoTick(_Symbol,tick);

//--- Lógica de compra e venda
   //COMPRA
   bool compra_mm_cros = mm_rapida_buffer[0] > mm_lenta_buffer[0] &&
                           mm_rapida_buffer[2] < mm_lenta_buffer[2];
                           
   bool compra_macd = macd_buffer[1] <= 0 && macd_buffer[0] > 0;
   
   //VENDA
   bool venda_mm_cros = mm_lenta_buffer[0] > mm_rapida_buffer[0] &&
                          mm_lenta_buffer[2] < mm_rapida_buffer[2];
                           
   bool venda_macd = macd_buffer[1] >= 0 && macd_buffer[0] < 0;
   
   bool Comprar = false;
   bool Vender  = false;
   
   if(estrategia == APENAS_MM)
     {
      Comprar  = compra_mm_cros;
      Vender   = venda_mm_cros;
     } else if(estrategia == APENAS_MACD)
              {
               Comprar  = compra_macd;
               Vender   = venda_macd;
              } else
                  {
                   Comprar = compra_macd || compra_mm_cros;
                   Vender  = venda_macd  || venda_mm_cros;
                  }

   
   //---Verifica Vela (Comprar na outra vela)
   bool TemosNovaVela = TemosNovaVela();
   
   if(TemosNovaVela && horaPodeOperar(inicio_op,fim_op))
     {
      //Condição de Compra
      if(Comprar && PositionSelect(ativoOp)==false && pode_operar)
        {
         desenhaLinhaVertical("Compra",velas[1].time,clrBlue);
         CompraAMercado(num_lots,ativoOp,tick.ask,TK,SL);
         beAtivo  = false;
         parAtivo = false;
        }
        
      //Condição de Venda
      if(Vender && PositionSelect(ativoOp)==false && pode_operar)
        {
         desenhaLinhaVertical("Venda",velas[1].time,clrRed);
         VendaAMercado(num_lots,ativoOp,tick.bid,TK,SL);
         beAtivo  = false;
         parAtivo = false;
        }
     }
      
   //---Controle Financeiro
   controle_financeiro_diario(ativoOp,lucro_max_dia,perda_max_dia);   
      
   if(NewDay())
     {
      pode_operar = true;
     }
     
   if(liga_breakeven == SIM && !beAtivo)
         {
            BreakEven(ativoOp,tick.last,PointBE,StartBE);
         }
         
   //---TS
   if(liga_train == SIM_TS)
     {
         realizartrailingstop(ativoOp,StartTS,velas[1].low,velas[1].high,tick.last);
         //TrailingStop(ativoOp,tick.last,StartTS,StepTS)
     }
   
   //---Parcial
   if(liga_par == SIM_PARCIAL && !parAtivo)
     {
         fazerParcial(ativoOp,nContrato,StartParcial,tick.last);
     } 
  
  //--- Controlar horário de limite
  if(TimeToString(TimeCurrent(),TIME_MINUTES) >= hora_limite_fecha_op && PositionSelect(ativoOp)==true)
    {
     Print("Encerrar todas as posições abertas!");
     
     FecharPosicao();
     pode_operar = false;
    }
   
  }
//+------------------------------------------------------------------+
