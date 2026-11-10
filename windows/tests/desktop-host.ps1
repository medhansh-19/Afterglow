param([ValidateSet('modern','legacy')][string]$Layout = 'modern')
$ErrorActionPreference = 'Stop'
# Native fixture for hosted Windows sessions without an Explorer shell. This is
# explicitly not Explorer; production code and IPC are left unchanged.
[Console]::WriteLine("fixture:starting:PID=$PID")
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class DesktopHostFixture {
  delegate IntPtr Procedure(IntPtr window, uint msg, UIntPtr wp, IntPtr lp);
  static Procedure callback = WndProc;
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct Class { public uint style; public IntPtr proc; public int clsExtra,winExtra; public IntPtr instance,icon,cursor,brush; public string menu,name; }
  [StructLayout(LayoutKind.Sequential)] struct Message { public IntPtr window; public uint msg; public UIntPtr wp; public IntPtr lp; public uint time; public int x,y; public uint extra; }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern ushort RegisterClass(ref Class cls);
  [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateWindowEx(uint ex,string cls,string title,uint style,int x,int y,int width,int height,IntPtr parent,IntPtr menu,IntPtr instance,IntPtr value);
  [DllImport("user32.dll")] static extern IntPtr DefWindowProc(IntPtr window,uint msg,UIntPtr wp,IntPtr lp);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window,IntPtr below,int x,int y,int width,int height,uint flags);
  [DllImport("user32.dll")] static extern bool SetLayeredWindowAttributes(IntPtr window,uint color,byte alpha,uint flags);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
  [DllImport("user32.dll")] static extern int GetMessage(out Message msg,IntPtr window,uint min,uint max);
  [DllImport("user32.dll")] static extern bool TranslateMessage(ref Message msg);
  [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref Message msg);
  [DllImport("gdi32.dll")] static extern IntPtr CreateSolidBrush(uint color);
  static IntPtr WndProc(IntPtr window,uint msg,UIntPtr wp,IntPtr lp) { return DefWindowProc(window,msg,wp,lp); }
  static IntPtr instance;
  static int left,top,width,height;
  static IntPtr Window(string cls,IntPtr parent,uint ex,bool visible) {
    var style=parent==IntPtr.Zero ? 0x80000000u : 0x40000000u;
    var window=CreateWindowEx(ex,cls,"Afterglow native desktop fixture",style|(visible?0x10000000u:0),parent==IntPtr.Zero?left:0,parent==IntPtr.Zero?top:0,width,height,parent,IntPtr.Zero,instance,IntPtr.Zero);
    Console.WriteLine("fixture:window:"+cls+":"+window);
    if(window==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    return window;
  }
  public static void Run(bool modern) {
    SetThreadDpiAwarenessContext(new IntPtr(-4)); instance=GetModuleHandle(null);
    left=GetSystemMetrics(76);top=GetSystemMetrics(77);width=GetSystemMetrics(78);height=GetSystemMetrics(79);
    if(width<=0||height<=0)throw new Exception("Hosted session has no display bounds.");
    foreach(var name in new[]{"Progman","WorkerW","SHELLDLL_DefView"}) {
      var cls=new Class{proc=Marshal.GetFunctionPointerForDelegate(callback),instance=instance,name=name,brush=name=="WorkerW"?CreateSolidBrush(0x804020):IntPtr.Zero};
      if(RegisterClass(ref cls)==0)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    const uint quiet=0x08000080u, layered=0x00080000u;
    if(modern) {
      var root=Window("Progman",IntPtr.Zero,quiet|0x00200000u,true);
      var background=Window("WorkerW",root,quiet,true);
      var icons=Window("SHELLDLL_DefView",root,quiet|layered,true);
      SetLayeredWindowAttributes(icons,0,0,2);
      SetWindowPos(background,new IntPtr(1),0,0,width,height,0x10);
      SetWindowPos(icons,IntPtr.Zero,0,0,width,height,0x10);
      SetWindowPos(root,new IntPtr(-1),left,top,width,height,0x10);
    } else {
      var root=Window("Progman",IntPtr.Zero,quiet|layered,true);
      SetLayeredWindowAttributes(root,0,0,2);
      SetWindowPos(root,new IntPtr(-1),left,top,width,height,0x10);
      var icons=Window("WorkerW",IntPtr.Zero,quiet|layered,true);
      Window("SHELLDLL_DefView",icons,quiet,true);
      SetLayeredWindowAttributes(icons,0,0,2);
      var background=Window("WorkerW",IntPtr.Zero,quiet,true);
      SetWindowPos(icons,new IntPtr(-1),left,top,width,height,0x10);
      SetWindowPos(background,new IntPtr(-1),left,top,width,height,0x10);
      SetWindowPos(icons,new IntPtr(-1),left,top,width,height,0x10);
    }
    Console.WriteLine("fixture:ready");
    Message msg;while(GetMessage(out msg,IntPtr.Zero,0,0)>0){TranslateMessage(ref msg);DispatchMessage(ref msg);}
  }
}
'@
[Console]::WriteLine('fixture:compiled')
[DesktopHostFixture]::Run($Layout -eq 'modern')
