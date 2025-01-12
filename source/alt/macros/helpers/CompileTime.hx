#if macro
package alt.macros.helpers;

class CompileTime
{
  public static var startTimeString:String;
  public static var endTimeString:String;

  public static var startTime:Float = 0;
  public static var endTime:Float = 0;

  public static function getToString(time:String = null)
    {
        switch(time) 
        {
            case 'start':
                startTimeString = Date.now().toString();
                return startTimeString;
            case 'end':
                endTimeString = Date.now().toString();
                return endTimeString;
            default:
                return null;
        }
    }
  
  public static function getFromString(time:String = null)
    {
        switch(time) 
        {
            case 'start':
                startTime = Date.now().getTime() / 1000;
                return startTime;
            case 'end':
                endTime = Date.now().getTime() / 1000;
                return endTime;
            case 'elapsed':
                startTime = Date.now().getTime() / 1000;
                endTime = Date.now().getTime() / 1000;
                return endTime - startTime;
            default:
                return 0;
        }
    }
  
}
#end
